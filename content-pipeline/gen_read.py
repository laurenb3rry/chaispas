#!/usr/bin/env python3
"""Generate Read passages (PLAN2 §3.6).

60 text-only passages from data/read_passages.json emulating broad real-world
source styles (news blurb, café/restaurant review, text-message exchange,
social post, travel blog, fiction vignette, recipe, practical email, event
listing, opinion snippet) across 4 difficulty tiers (0-3, aligned with the
concept-graph tiers). Each passage: 60-200 French words, a per-word gloss map
covering the content words (powers tap-a-word in the Reader), and 2-3
tap-answer comprehension questions. No audio in v2 (passage TTS deferred).

Style diversity is a validation criterion: validate.py --v2c errors if any
style exceeds 8 passages (the spec file ships 6 per style).

Output: read.json  (validate.py --v2c -> read_validated.json)

Usage:
    python gen_read.py                        # everything missing
    python gen_read.py --passage rd_texto_01
    python gen_read.py --passage rd_texto_01 --force
    python gen_read.py --dry-run
"""

import argparse
import json
import re

from gen_listen import shuffle_answers
from genlib import (HERE, STREET_REGISTER_BRIEF, call_claude, load_output,
                    make_client, save_output)

SPECS_PATH = HERE / "data" / "read_passages.json"
OUT_PATH = HERE / "read.json"

# Per-style dial: what the text is, and which register it teaches. "street"
# styles get the register brief appended; the others (news, email, recipe,
# event) deliberately exercise standard written French — Read is the one mode
# where the formal end of the register spectrum is first-class.
STYLES = {
    "news": {
        "label": "news blurb",
        "brief": "A short local-news item like those in 20 Minutes or actu.fr: factual and "
                 "concrete (places, days, numbers), with one short quote from a resident or "
                 "official where natural. Journalistic but accessible.",
        "register": "Standard written French in the prose — no street register; a quoted "
                    "person may speak casually.",
        "street": False,
    },
    "review": {
        "label": "café/restaurant review",
        "brief": "A customer review like on Google Maps: first person, concrete details "
                 "(what they ordered, prices, service, wait), and a clear verdict with a "
                 "star-rating feel. The enthusiasm or disappointment must feel genuine.",
        "register": "Casual written French — contractions and spoken turns of phrase "
                    "welcome (c'est, y'a), light street register where natural.",
        "street": True,
    },
    "texto": {
        "label": "text-message exchange",
        "brief": "A WhatsApp/SMS thread between two friends, one message per line, each "
                 "line formatted 'Prénom : message'. 8-14 short messages with real "
                 "back-and-forth: questions, reactions, teasing. At most 2 emoji total.",
        "register": "HEAVY street register — this style is the pack's street-French "
                    "showcase. Ne-drop everywhere, t'as/t'es, chais pas, fillers (bah, du "
                    "coup, grave), and a handful of common SMS abbreviations (slt, jsp, "
                    "tkt, mdr, bcp) — every abbreviation must appear in the gloss map.",
        "street": True,
    },
    "social": {
        "label": "social-media post",
        "brief": "A post in a neighborhood Facebook group or an Instagram caption: first "
                 "person, addressed to neighbors/followers, a concrete ask or story, at "
                 "most 3 hashtags.",
        "register": "Casual written French with light street register (c'est pas, y'a).",
        "street": True,
    },
    "travel": {
        "label": "travel blog excerpt",
        "brief": "An excerpt from a personal travel blog: first-person narration, sensory "
                 "detail, one or two practical tips, a warm closing line.",
        "register": "Casual written French; light spoken forms welcome.",
        "street": True,
    },
    "fiction": {
        "label": "short fiction vignette",
        "brief": "A slice-of-life vignette with one small arc (something shifts by the "
                 "end). Third or first person. A line or two of dialogue welcome.",
        "register": "Written narration in standard French; any dialogue lines in "
                    "realistic spoken register.",
        "street": True,
    },
    "recipe": {
        "label": "recipe",
        "brief": "A simple home recipe: a one-sentence pitch, an ingredient list with "
                 "quantities (one per line), then short numbered steps. One practical tip "
                 "at the end.",
        "register": "Standard written French; steps in the infinitive or vous-imperative.",
        "street": False,
    },
    "email": {
        "label": "practical email",
        "brief": "A real-life practical email: subject line ('Objet : ...'), greeting, "
                 "purpose, concrete details (dates, numbers), polite close, sign-off "
                 "name. The kind of email you actually have to write in France.",
        "register": "Polite formal written French (vouvoiement) — this style teaches the "
                    "formal end of the register spectrum.",
        "street": False,
    },
    "event": {
        "label": "event listing",
        "brief": "A local event listing/flyer: what, where, when, price, practical info. "
                 "Short lines or mini-paragraphs; telegraphic style welcome where a real "
                 "flyer would use it.",
        "register": "Standard written French.",
        "street": False,
    },
    "opinion": {
        "label": "opinion snippet",
        "brief": "A short opinion piece like a magazine column or reader letter: a clear "
                 "stance stated early, 2-3 concrete arguments, a punchy close. Rhetorical "
                 "questions welcome.",
        "register": "Lively written French between casual and standard; light spoken "
                    "forms for effect.",
        "street": True,
    },
}

# Per-tier dial: length, question count, and grammar ceiling (mirrors the
# concept-graph tiers so Read scores can map to comprehension mastery).
TIERS = {
    0: {"words": (60, 90), "questions": 2,
        "brief": "Grammar ceiling: present tense; c'est + adjective/noun; simple ne-less "
                 "negation (pas); je veux / je vais + infinitive at most. Short simple "
                 "sentences, very high-frequency vocabulary, generous cognates."},
    1: {"words": (80, 120), "questions": 2,
        "brief": "Grammar ceiling: present tense, futur proche (aller + infinitive), "
                 "modal verbs (vouloir/pouvoir/devoir + infinitive), intonation "
                 "questions. Everyday vocabulary, cognates welcome."},
    2: {"words": (110, 160), "questions": 3,
        "brief": "Adds passé composé, object pronouns, y/en. Broader everyday "
                 "vocabulary and natural sentence rhythm."},
    3: {"words": (140, 200), "questions": 3,
        "brief": "Full everyday texture: imparfait vs passé composé, relative clauses "
                 "(qui/que), conditional softeners, idiomatic reactions. Natural "
                 "vocabulary breadth — still everyday France, no literary rarities."},
}

# "j'habite" and "aujourd'hui" count as one word each
WORD = re.compile(r"[\wà-ÿœæ]+(?:'[\wà-ÿœæ]+)*")


def count_words(text):
    return len(WORD.findall(text.replace("’", "'")))


def build_prompt(spec, style, tier):
    lo, hi = tier["words"]
    n_q = tier["questions"]
    street = f"\n{STREET_REGISTER_BRIEF}\n" if style["street"] else ""
    return f"""You are writing a Read passage for "Chais Pas", a spoken-French course. Read mode gives wide exposure to real-world French text styles: the learner reads the passage, taps any word to see an English gloss, then answers comprehension questions. The passage must read like the real thing, not a textbook text.

PASSAGE: {spec['title']}
STYLE: {style['label']}. {style['brief']}
REGISTER: {style['register']}
TOPIC: {spec['topic']}

TIER {spec['tier']} (of 0-3). {tier['brief']}
LENGTH: a HARD budget of {lo}-{hi} French words — aim for the middle of that range; undershooting the minimum is as much a failure as exceeding the maximum.
{street}
TASK — return ONLY a JSON object with three keys:

1. "body": the passage text. Plain text as it would appear in the source medium — no markdown, no headers. Use \\n for line breaks where the style needs them (messages, list items, email lines). Use straight apostrophes ('). The title is displayed separately; do not repeat it as a first line.

2. "gloss": an object mapping surface forms from the body to short English glosses — this powers tap-a-word. Cover EVERY content word: nouns, verbs (as conjugated in the text), adjectives, adverbs, fixed expressions, street forms and abbreviations. Skip only articles, subject pronouns, numbers, proper names, and basic prepositions (de, à, dans...). Keys lowercase and spelled EXACTLY as in the body (keep accents; keep elided forms whole: "j'habite": "I live"). One entry per distinct form.

3. "questions": exactly {n_q} comprehension questions about facts in the passage (not vocabulary trivia). Each: {{"question": "...", "options": ["...", "...", "...", "..."], "answer_index": 0-3}}. Questions and options in English, short. Distractors plausible — mentioned-but-wrong beats absurd. Each question must hinge on a different part of the passage.

Output ONLY the JSON object, no prose, no code fences."""


def passage_from_gen(spec, tier, gen):
    pid = spec["id"]
    body = gen["body"].strip()
    gloss = {k.strip().lower().replace("’", "'"): str(v).strip()
             for k, v in gen["gloss"].items() if k.strip() and str(v).strip()}
    return {
        "id": pid,
        "title": spec["title"],
        "style": spec["style"],
        "tier": spec["tier"],
        "topic": spec["topic"],
        "body": body,
        "word_count": count_words(body),
        "gloss": gloss,
        "questions": shuffle_answers(pid, [
            {"question": q["question"].strip(),
             "options": [o.strip() for o in q["options"]],
             "answer_index": int(q["answer_index"])}
            for q in gen["questions"]]),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--passage", action="append", help="passage id(s), e.g. rd_texto_01")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(SPECS_PATH) as f:
        specs = json.load(f)["passages"]
    out = load_output(OUT_PATH, "passages")
    done = {p["id"] for p in out["passages"]}
    client = None if args.dry_run else make_client()

    for spec in specs:
        pid = spec["id"]
        if args.passage and pid not in args.passage:
            continue
        if pid in done and not args.force:
            print(f"[skip] {pid} (exists; --force to redo)")
            continue
        style, tier = STYLES[spec["style"]], TIERS[spec["tier"]]
        print(f"[gen ] {pid} ({spec['style']}, tier {spec['tier']}): {spec['title']}")
        if args.dry_run:
            print(build_prompt(spec, style, tier) + "\n" + "=" * 80)
            continue

        lo, hi = tier["words"]
        for attempt in range(3):
            prompt = build_prompt(spec, style, tier)
            if attempt:
                prompt += (f"\n\nIMPORTANT — a previous attempt wrote {words} French words, "
                           f"outside the {lo}-{hi} budget. Hit the budget this time; adjust "
                           f"sentence richness, not just sentence count.")
            gen = call_claude(client, prompt, label=pid)
            for key in ("body", "gloss", "questions"):
                if not gen.get(key):
                    raise RuntimeError(f"{pid}: missing '{key}' in generation result")
            if len(gen["questions"]) != tier["questions"]:
                print(f"    {len(gen['questions'])} questions (want {tier['questions']}) "
                      f"(attempt {attempt + 1})")
                words = count_words(gen["body"])
                continue
            words = count_words(gen["body"])
            if lo * 0.9 <= words <= hi * 1.15:
                break
            print(f"    {words} words outside budget {lo}-{hi} (attempt {attempt + 1})")
        else:
            print(f"    WARNING: keeping last attempt despite size ({words} words)")
        passage = passage_from_gen(spec, tier, gen)
        out["passages"] = [p for p in out["passages"] if p["id"] != pid] + [passage]
        save_output(OUT_PATH, out)
        print(f"       {passage['word_count']} words, {len(passage['gloss'])} gloss entries, "
              f"{len(passage['questions'])} questions written")

    print(f"\nTotal passages in {OUT_PATH.name}: {len(out['passages'])}")


if __name__ == "__main__":
    main()
