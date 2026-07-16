#!/usr/bin/env python3
"""Generate the Learn/Grammar module (PLAN2 §3.3).

15 focused rule lessons from data/grammar_lessons.json. Each lesson becomes a
ConceptNode of type `grammar`: a <= 200-word explanation in the MT
conversational voice, 6-8 canonical examples (formal + street + English), and
20 drill sentences.

Output: learn_grammar.json

Usage:
    python gen_grammar.py                          # all lessons
    python gen_grammar.py --lesson gram_gender_articles
    python gen_grammar.py --dry-run
"""

import argparse
import json

from genlib import (EXPLANATION_SCHEMA, HERE, STREET_REGISTER_BRIEF, VOICE_SPEC,
                    call_claude, exemplar_block, exemplar_explanation, load_output,
                    load_v1_graph, make_client, save_output, v1_concept_summaries)

LESSONS_PATH = HERE / "data" / "grammar_lessons.json"
OUT_PATH = HERE / "learn_grammar.json"
N_DRILLS = 20
N_EXAMPLES = 7  # spec: 6-8


def build_prompt(lesson, graph):
    focus = "\n".join(f"- {b}" for b in lesson["focus"])
    return f"""You are writing a grammar lesson for "Chais Pas", a spoken-French course with a first-class street-register layer. The learner knows the v1 curriculum below.

LESSON: {lesson['title']}
COVER THESE POINTS:
{focus}
Street angle: {lesson['street_angle']}

V1 CURRICULUM (grammar the learner already has — lean on it, don't re-teach it):
{v1_concept_summaries(graph)}

{STREET_REGISTER_BRIEF}

{VOICE_SPEC}

TASK — return a JSON object with three keys:

1. {EXPLANATION_SCHEMA}
   - Grammar lessons get the fullest treatment: 4-6 sections, total word count across headers, bodies and bullets between 180 and 300 — treat 300 as a hard ceiling and cut any section that doesn't teach something new. Density beats length.
   - Every focus point above must be taught somewhere in the sections; the street angle gets its own section or is woven in — never bolted on as an afterthought.

{exemplar_block('grammar')}

2. "examples": exactly {N_EXAMPLES} canonical examples, each {{"english": "...", "formal": "...", "street": "..."}}. They must ladder in difficulty and between them demonstrate every focus point above. street applies the register rules (or equals formal when nothing applies).

3. "drills": exactly {N_DRILLS} drill sentences exercising the lesson. Requirements:
   - every sentence makes the learner USE this lesson's rule (not just contain it)
   - everyday-France content, short spoken French (3-10 words), difficulty ladders from 2-4 word combos to full sentences
   - vocabulary: prefer words from the v1 curriculum examples plus obvious cognates; no rare vocabulary
   - each: {{"english": "...", "french_formal": "...", "french_street": "...", "concept_ids": [v1 concept ids actually used]}}
   - no duplicates, no near-duplicates

Output ONLY the JSON object, no prose, no code fences."""


def node_for_lesson(lesson, gen):
    nid = lesson["id"]
    examples = [{"english": e["english"].strip(), "formal": e["formal"].strip(),
                 "street": e["street"].strip()} for e in gen["examples"]]
    drills = []
    for i, d in enumerate(gen["drills"], 1):
        drills.append({
            "id": f"{nid}_{i:03d}",
            "target_concept_id": nid,
            "concept_ids": sorted(set(d.get("concept_ids", [])) | {nid}),
            "english": d["english"].strip(),
            "french_formal": d["french_formal"].strip(),
            "french_street": d["french_street"].strip(),
        })
    return {
        "id": nid,
        "type": "grammar",
        "tier": lesson["tier"],
        "prereq_ids": lesson["prereq_ids"],
        "title": lesson["title"],
        # approved exemplar explanations ship verbatim
        "explanation": exemplar_explanation(nid) or gen["explanation"],
        "canonical_examples": examples,
        "drills": drills,
    }


# --- phase 10b: explanation-only regeneration (drills/examples/audio kept) ---

EXPLANATION_ONLY_PROMPT = """{voice}

You are rewriting the learner-facing explanation for one grammar lesson of "Chais Pas", a spoken-French course with a first-class street-register layer. The lesson's canonical examples and drills already exist — write ONLY the explanation.

LESSON: {title}
COVER THESE POINTS:
{focus}
Street angle: {street_angle}

ITS CANONICAL EXAMPLES (already fixed — your explanation should set them up, not contradict them):
{examples}

{schema}
- Grammar lessons get the fullest treatment: 4-6 sections, total word count across headers, bodies and bullets between 180 and 300 — treat 300 as a hard ceiling. Density beats length.
- Every focus point above must be taught somewhere in the sections.

{exemplars}

Return ONLY a JSON object: {{"explanation": [ ...sections... ]}}"""


def regen_explanation(client, lesson, node):
    examples = "\n".join(f"  {e['formal']} / street: {e['street']} ({e['english']})"
                         for e in node.get("canonical_examples", []))
    prompt = EXPLANATION_ONLY_PROMPT.format(
        voice=VOICE_SPEC, title=lesson["title"],
        focus="\n".join(f"- {b}" for b in lesson["focus"]),
        street_angle=lesson["street_angle"], examples=examples,
        schema=EXPLANATION_SCHEMA, exemplars=exemplar_block("grammar"))
    gen = call_claude(client, prompt, label=lesson["id"])
    if not isinstance(gen, dict) or not isinstance(gen.get("explanation"), list):
        raise RuntimeError(f"{lesson['id']}: explanation regen returned wrong shape")
    return gen["explanation"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lesson", action="append", help="lesson id(s), e.g. gram_gender_articles")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--explanations-only", action="store_true",
                    help="phase 10b: regenerate explanations for EXISTING lessons "
                         "without touching their examples or drills")
    args = ap.parse_args()

    with open(LESSONS_PATH) as f:
        lessons = json.load(f)["lessons"]
    graph = load_v1_graph()
    out = load_output(OUT_PATH, "nodes")
    done = {n["id"] for n in out["nodes"]}
    client = None if args.dry_run else make_client()

    if args.explanations_only:
        lessons_by_id = {l["id"]: l for l in lessons}
        for node in out["nodes"]:
            nid = node["id"]
            if args.lesson and nid not in args.lesson:
                continue
            # resumable: structured explanations are lists, legacy are strings
            if isinstance(node.get("explanation"), list) and not args.force:
                print(f"[skip] {nid} (already structured; --force to redo)")
                continue
            print(f"[expl] {nid}")
            if args.dry_run:
                continue
            node["explanation"] = exemplar_explanation(nid) \
                or regen_explanation(client, lessons_by_id[nid], node)
            save_output(OUT_PATH, out)
        print(f"\nexplanations refreshed; {len(out['nodes'])} lessons in {OUT_PATH.name}")
        return

    for lesson in lessons:
        nid = lesson["id"]
        if args.lesson and nid not in args.lesson:
            continue
        if nid in done and not args.force:
            print(f"[skip] {nid} (exists; --force to redo)")
            continue
        print(f"[gen ] {nid}: {lesson['title']}")
        if args.dry_run:
            print(build_prompt(lesson, graph) + "\n" + "=" * 80)
            continue

        gen = call_claude(client, build_prompt(lesson, graph), label=nid)
        for key in ("explanation", "examples", "drills"):
            if not gen.get(key):
                raise RuntimeError(f"{nid}: missing '{key}' in generation result")
        node = node_for_lesson(lesson, gen)
        out["nodes"] = [n for n in out["nodes"] if n["id"] != nid] + [node]
        save_output(OUT_PATH, out)
        print(f"       {len(node['canonical_examples'])} examples, {len(node['drills'])} drills written")

    print(f"\nTotal grammar lessons in {OUT_PATH.name}: {len(out['nodes'])}")


if __name__ == "__main__":
    main()
