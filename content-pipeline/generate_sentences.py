#!/usr/bin/env python3
"""Generate drill sentences per concept via the Claude API.

For each concept node in graph.json, generates N drill sentences that use ONLY
that concept plus its transitive prerequisites (the DAG constraint from PLAN.md
section 2.1). Output: sentences.json.

Usage:
    python generate_sentences.py                  # all concepts, default N
    python generate_sentences.py --concept je_veux --n 40
    python generate_sentences.py --dry-run        # print prompts, no API calls
"""

import argparse
import json
import re
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

MODEL = "claude-sonnet-4-6"
DEFAULT_N = 40  # PLAN.md asks for 30-60 per concept
MAX_TOKENS = 16000

HERE = Path(__file__).parent
GRAPH_PATH = HERE / "graph.json"
OUT_PATH = HERE / "sentences.json"


def load_graph():
    with open(GRAPH_PATH) as f:
        return json.load(f)


def ancestors(node_id, nodes_by_id, acc=None):
    """Transitive prerequisite closure of a node (excluding the node itself)."""
    if acc is None:
        acc = set()
    for pid in nodes_by_id[node_id]["prereq_ids"]:
        if pid not in acc:
            acc.add(pid)
            ancestors(pid, nodes_by_id, acc)
    return acc


def topo_order(nodes):
    nodes_by_id = {n["id"]: n for n in nodes}
    order, seen = [], set()

    def visit(nid):
        if nid in seen:
            return
        seen.add(nid)
        for pid in nodes_by_id[nid]["prereq_ids"]:
            visit(pid)
        order.append(nid)

    for n in sorted(nodes, key=lambda n: n["tier"]):
        visit(n["id"])
    return order


def concept_summary(node):
    ex = "; ".join(
        f"\"{e['formal']}\" / street: \"{e['street']}\" ({e['english']})"
        for e in node["canonical_examples"][:4]
    )
    return f"- {node['id']} ({node['type']}): {node['title']}. Examples: {ex}"


def build_prompt(target, allowed_nodes, n):
    allowed_ids = [a["id"] for a in allowed_nodes]
    summaries = "\n".join(concept_summary(a) for a in allowed_nodes)
    target_examples = json.dumps(target["canonical_examples"], ensure_ascii=False, indent=2)

    questions_allowed = "questions_intonation" in allowed_ids or target["type"] == "chunk"
    question_rule = (
        "Questions are allowed."
        if questions_allowed
        else "Do NOT produce questions — the question concept has not been introduced yet. Statements only."
    )
    negation_allowed = "negation_pas" in allowed_ids
    negation_rule = (
        "Negation with 'pas' is allowed (formal: ne...pas; street: ne-drop, pas alone)."
        if negation_allowed
        else "Do NOT use negation — it has not been introduced yet."
    )

    return f"""You are generating drill sentences for a Michel Thomas-style French audio course. The learner builds sentences from English prompts, so every sentence must be constructible from ONLY the concepts listed below — this is a hard constraint.

TARGET CONCEPT (every sentence must exercise this):
{json.dumps({k: target[k] for k in ('id', 'type', 'title', 'explanation', 'street_mapping')}, ensure_ascii=False, indent=2)}

Canonical examples of the target concept:
{target_examples}

ALLOWED CONCEPTS (the complete set — the target plus its prerequisites):
{summaries}

HARD RULES:
1. Every sentence MUST use the target concept ({target['id']}).
2. Every sentence may ONLY use grammar/constructions from the allowed concepts above. If a construction (past tense, future, object pronouns, questions, relative clauses, conditional, reflexives...) is not in the allowed list, it must not appear.
3. {question_rule}
4. {negation_rule}
5. Vocabulary: restrict to (a) words appearing in the canonical examples above, (b) obvious English-French cognates ending in -tion/-able/-ible/-aire{" (allowed: cognate_bridges is in the set)" if "cognate_bridges" in allowed_ids else " — NOT allowed here, cognate_bridges is not in the set"}, (c) closed-class function words (articles, prepositions, subject pronouns, numbers). No other vocabulary.
6. french_street must apply the street register of every allowed register concept: ne-drop only if negation is allowed, on-for-nous only if introduced, reductions like j'veux/t'as/y'a per the street_mapping notes. If no register rule applies, french_street may equal french_formal.
7. Vary length: start with 2-4 word combos, build to fuller sentences. Vary persons/forms covered by the allowed concepts. No duplicates, no near-duplicates.
8. concept_ids: list every allowed concept the sentence actually uses (always including {target['id']}). Never list a concept outside the allowed set.
9. Canonical examples may preview material beyond the allowed set (negation, questions). If an example conflicts with rules 2-4, do NOT imitate that aspect — the rules win.

Generate exactly {n} drill sentences.

Output ONLY a JSON array, no prose, no code fences:
[{{"english": "...", "french_formal": "...", "french_street": "...", "concept_ids": ["..."]}}]"""


def parse_response(text):
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    start, end = text.find("["), text.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("no JSON array in response")
    return json.loads(text[start : end + 1])


def generate_for_concept(client, target, allowed_nodes, n):
    prompt = build_prompt(target, allowed_nodes, n)
    for attempt in range(3):
        try:
            resp = client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                messages=[{"role": "user", "content": prompt}],
            )
            items = parse_response(resp.content[0].text)
            if not isinstance(items, list) or not items:
                raise ValueError("empty or non-list result")
            return items
        except Exception as e:
            print(f"    attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"generation failed for {target['id']} after 3 attempts")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--concept", action="append", help="only generate for these concept ids")
    ap.add_argument("--n", type=int, default=DEFAULT_N, help="sentences per concept (30-60)")
    ap.add_argument("--force", action="store_true", help="regenerate concepts already in sentences.json")
    ap.add_argument("--dry-run", action="store_true", help="print prompts without calling the API")
    args = ap.parse_args()

    if not 30 <= args.n <= 60:
        sys.exit("--n must be in [30, 60] per PLAN.md")

    load_dotenv(HERE / ".env")
    graph = load_graph()
    nodes_by_id = {n["id"]: n for n in graph["nodes"]}
    order = topo_order(graph["nodes"])
    targets = [nid for nid in order if not args.concept or nid in args.concept]

    existing = {"version": 1, "sentences": []}
    if OUT_PATH.exists():
        with open(OUT_PATH) as f:
            existing = json.load(f)
    done = {s["target_concept_id"] for s in existing["sentences"]}

    client = None
    if not args.dry_run:
        import anthropic

        client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY

    for nid in targets:
        target = nodes_by_id[nid]
        allowed_ids = sorted(ancestors(nid, nodes_by_id) | {nid})
        allowed_nodes = [nodes_by_id[a] for a in allowed_ids]

        if nid in done and not args.force:
            print(f"[skip] {nid} (already generated; use --force to redo)")
            continue

        print(f"[gen ] {nid} — allowed set: {allowed_ids}")
        if args.dry_run:
            print(build_prompt(target, allowed_nodes, args.n))
            print("\n" + "=" * 80 + "\n")
            continue

        items = generate_for_concept(client, target, allowed_nodes, args.n)
        existing["sentences"] = [
            s for s in existing["sentences"] if s["target_concept_id"] != nid
        ]
        for i, item in enumerate(items, 1):
            existing["sentences"].append(
                {
                    "id": f"{nid}_{i:03d}",
                    "target_concept_id": nid,
                    "concept_ids": sorted(set(item.get("concept_ids", [])) | {nid}),
                    "english": item["english"].strip(),
                    "french_formal": item["french_formal"].strip(),
                    "french_street": item["french_street"].strip(),
                }
            )
        with open(OUT_PATH, "w") as f:
            json.dump(existing, f, ensure_ascii=False, indent=2)
        print(f"       {len(items)} sentences written")

    print(f"\nTotal sentences in {OUT_PATH.name}: {len(existing['sentences'])}")


if __name__ == "__main__":
    main()
