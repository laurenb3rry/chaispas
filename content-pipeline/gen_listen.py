#!/usr/bin/env python3
"""Generate Listen episodes (PLAN2 §3.5).

30 two-person street-register dialogues from data/listen_episodes.json across
4 difficulty levels (A: slow-ish street, short -> D: full-speed street with
fillers/reductions, 60-90s). Each episode: per-line transcript with English
gloss, 3 tap-answer comprehension questions, per-line audio refs (fast + slow)
and full-episode audio refs (concatenated by tts.py). Two distinct WaveNet
voices per episode for speaker separation.

Output: listen.json  (validate.py --v2b -> listen_validated.json)

Usage:
    python gen_listen.py                     # everything missing
    python gen_listen.py --episode lst_b01
    python gen_listen.py --episode lst_b01 --force
    python gen_listen.py --dry-run
"""

import argparse
import json
import random

from genlib import (HERE, STREET_REGISTER_BRIEF, call_claude, load_output,
                    make_client, save_output)

SPECS_PATH = HERE / "data" / "listen_episodes.json"
OUT_PATH = HERE / "listen.json"
N_QUESTIONS = 3

# Per-level dial: dialogue size, speaking rates, and register intensity.
LEVELS = {
    "A": {"lines": (6, 8), "chars": (200, 420), "rate_fast": 1.0, "rate_slow": 0.8,
          "brief": "Short, simple sentences, mostly present tense. Light street register "
                   "(ne-drop, on for nous) and only occasional fillers (ouais, bon). "
                   "A motivated beginner should follow it on the second listen."},
    "B": {"lines": (8, 10), "chars": (380, 680), "rate_fast": 1.1, "rate_slow": 0.8,
          "brief": "Everyday conversational French. Regular street register (ne-drop, t'as, "
                   "y'a) and common fillers (bah, du coup, en fait). One or two passé "
                   "composé stories are fine."},
    "C": {"lines": (10, 13), "chars": (580, 950), "rate_fast": 1.2, "rate_slow": 0.85,
          "brief": "Fast natural chat between friends. Full street register incl. reductions "
                   "(chais pas, j'suis, faut) and frequent fillers (bah, du coup, genre, "
                   "bref, quoi). Reactions and interruption-like short turns welcome."},
    "D": {"lines": (14, 18), "chars": (1300, 1900), "rate_fast": 1.3, "rate_slow": 0.9,
          "brief": "Full-speed native gossip/venting. Heavy fillers and reductions, "
                   "colloquial reactions (grave, carrément, n'importe quoi, ça me saoule), "
                   "trailing sentences, back-channel turns. 60-90 seconds of audio: most "
                   "turns are meaty 2-3 sentence stretches of storytelling with concrete "
                   "detail, not one-liners."},
}


def build_prompt(spec, level):
    lo, hi = level["lines"]
    clo, chi = level["chars"]
    s1, s2 = spec["speakers"][0]["label"], spec["speakers"][1]["label"]
    return f"""You are writing a listening-comprehension episode for "Chais Pas", a spoken-French course whose Listen mode trains the learner's ear on real street French. The dialogue is synthesized to audio and heard cold (no transcript) first, so it must sound like two real French people, not a textbook.

EPISODE: {spec['title']}
TOPIC: {spec['topic']}
SPEAKERS: speaker 1 = {s1}, speaker 2 = {s2}. Two friends/interlocutors, informal (tutoiement) unless the topic implies a service call.

LEVEL {spec['level']} — {level['brief']}
SIZE: {lo}-{hi} lines total, and a HARD budget of {clo}-{chi} characters of French across all lines — aim for the middle of that range; undershooting the minimum is as much a failure as exceeding the maximum. Lines alternate speakers (an occasional double turn by the same speaker is OK if natural).

{STREET_REGISTER_BRIEF}

TASK — return ONLY a JSON object with two keys:

1. "lines": the dialogue, in order. Each: {{"speaker": 1 or 2, "french_street": "...", "english": "..."}}. french_street is exactly what is spoken (street register per the level); english is a faithful, natural gloss. Write French that text-to-speech can render: spell out reductions as real words (t'as, y'a, chais pas), no phonetic respelling beyond established street forms, no stage directions.

2. "questions": exactly {N_QUESTIONS} comprehension questions about facts in the dialogue (not vocabulary trivia). Each: {{"question": "...", "options": ["...", "...", "...", "..."], "answer_index": 0-3}}. Questions and options in English, short. Distractors plausible — mentioned-but-wrong beats absurd. Vary which position holds the right answer.

The dialogue must have a concrete arc (something happens or gets decided), everyday-France texture, and the three questions must each hinge on a different part of it.

Output ONLY the JSON object, no prose, no code fences."""


def shuffle_answers(eid, questions):
    """Reassign correct answers to distinct option positions (seeded by episode
    id) — the model clusters them, which makes tap-answers guessable."""
    rng = random.Random(eid)
    targets = rng.sample(range(4), len(questions))
    for q, target in zip(questions, targets):
        i = q["answer_index"]
        q["options"][i], q["options"][target] = q["options"][target], q["options"][i]
        q["answer_index"] = target
    return questions


def episode_from_gen(spec, level, gen):
    eid = spec["id"]
    lines = []
    for i, l in enumerate(gen["lines"], 1):
        line_id = f"{eid}_l{i:02d}"
        lines.append({
            "line_id": line_id,
            "speaker": int(l["speaker"]),
            "french_street": l["french_street"].strip(),
            "english": l["english"].strip(),
            "audio_refs": {"fast": f"{line_id}_fast.mp3", "slow": f"{line_id}_slow.mp3"},
        })
    total_chars = sum(len(l["french_street"]) for l in lines)
    # ~17 chars/sec of French at rate 1.0 (measured from the synthesized pack),
    # plus the inter-line gaps added at concat
    est = round(total_chars / (17 * level["rate_fast"]) + 0.5 * (len(lines) - 1))
    return {
        "id": eid,
        "title": spec["title"],
        "level": spec["level"],
        "topic": spec["topic"],
        "speakers": spec["speakers"],
        "rate_fast": level["rate_fast"],
        "rate_slow": level["rate_slow"],
        "est_duration_sec": est,
        "lines": lines,
        "questions": shuffle_answers(eid, [
            {"question": q["question"].strip(),
             "options": [o.strip() for o in q["options"]],
             "answer_index": int(q["answer_index"])}
            for q in gen["questions"]]),
        "audio_refs": {"full_fast": f"{eid}_full_fast.mp3",
                       "full_slow": f"{eid}_full_slow.mp3"},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--episode", action="append", help="episode id(s), e.g. lst_b01")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(SPECS_PATH) as f:
        specs = json.load(f)["episodes"]
    out = load_output(OUT_PATH, "episodes")
    done = {e["id"] for e in out["episodes"]}
    client = None if args.dry_run else make_client()

    for spec in specs:
        eid = spec["id"]
        if args.episode and eid not in args.episode:
            continue
        if eid in done and not args.force:
            print(f"[skip] {eid} (exists; --force to redo)")
            continue
        level = LEVELS[spec["level"]]
        print(f"[gen ] {eid} (level {spec['level']}): {spec['title']}")
        if args.dry_run:
            print(build_prompt(spec, level) + "\n" + "=" * 80)
            continue

        clo, chi = level["chars"]
        for attempt in range(3):
            prompt = build_prompt(spec, level)
            if attempt:
                prompt += (f"\n\nIMPORTANT — a previous attempt wrote {chars} characters "
                           f"of French, outside the {clo}-{chi} budget. Hit the budget "
                           f"this time; adjust line length, not just line count.")
            gen = call_claude(client, prompt, label=eid)
            for key in ("lines", "questions"):
                if not gen.get(key):
                    raise RuntimeError(f"{eid}: missing '{key}' in generation result")
            chars = sum(len(l["french_street"]) for l in gen["lines"])
            if clo * 0.9 <= chars <= chi * 1.2:
                break
            print(f"    {chars} chars outside budget {clo}-{chi} (attempt {attempt + 1})")
        else:
            print(f"    WARNING: keeping last attempt despite size ({chars} chars)")
        episode = episode_from_gen(spec, level, gen)
        out["episodes"] = [e for e in out["episodes"] if e["id"] != eid] + [episode]
        save_output(OUT_PATH, out)
        chars = sum(len(l["french_street"]) for l in episode["lines"])
        print(f"       {len(episode['lines'])} lines, {chars} chars, "
              f"~{episode['est_duration_sec']}s, {len(episode['questions'])} questions written")

    print(f"\nTotal episodes in {OUT_PATH.name}: {len(out['episodes'])}")


if __name__ == "__main__":
    main()
