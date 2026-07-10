#!/usr/bin/env python3
"""Generate Speak scenarios (PLAN2 §3.4).

12 everyday-France scenarios from data/scenarios.json, each a branching
scripted dialogue 8-14 exchanges deep with 2-3 branch points, generated in
3 variants so replays differ. User lines carry an English intent prompt,
target French (street primary, formal alternate) and audio refs; NPC lines
carry street French, an English gloss, and street_fast/street_slow audio refs.

Output: scenarios.json  (validate.py --v2b -> scenarios_validated.json)

Usage:
    python gen_scenarios.py                        # everything missing
    python gen_scenarios.py --scenario scn_cafe    # one scenario (all variants)
    python gen_scenarios.py --scenario scn_cafe --variant 2 --force
    python gen_scenarios.py --dry-run
"""

import argparse
import json

from genlib import (HERE, STREET_REGISTER_BRIEF, call_claude, load_output,
                    load_v1_graph, make_client, save_output, v1_concept_summaries)
from validate import SCN_BRANCH_RANGE, SCN_PATH_RANGE, walk_variant

SPECS_PATH = HERE / "data" / "scenarios.json"
OUT_PATH = HERE / "scenarios.json"
N_VARIANTS = 3


def build_prompt(spec, variant_no, graph, prior_user_lines):
    beats = "\n".join(f"- {b}" for b in spec["beats"])
    branch_ideas = "\n".join(f"- {b}" for b in spec["branch_ideas"])
    differ = ""
    if prior_user_lines:
        lines = "\n".join(f'- "{line}"' for line in prior_user_lines[:30])
        differ = f"""
EARLIER VARIANTS of this scenario already used these user lines — this variant must take a
noticeably different path (different items, wording, and complications):
{lines}
"""
    return f"""You are writing variant {variant_no} of {N_VARIANTS} of a Speak scenario for "Chais Pas", a spoken-French course teaching everyday-France survival in real street register. The learner sees an English prompt, says the French line ALOUD, then hears the native line and self-grades. NPC lines are heard as audio first (fast street register), so they must sound like a real French person, not a textbook.

SCENARIO: {spec['title']}
NPC ROLE: {spec['npc_role']}
USER GOAL: {spec['user_goal']}
THIS VARIANT'S ANGLE: {spec['variant_angles'][variant_no - 1]}

BEATS the dialogue must cover, in a natural order:
{beats}

BRANCH IDEAS (pick 2-3, adapted to this variant's angle):
{branch_ideas}
{differ}
LEARNER LEVEL — the learner has this grammar; stay inside it where possible and keep vocabulary everyday (A2-ish, obvious cognates welcome, no rare words):
{v1_concept_summaries(graph)}

{STREET_REGISTER_BRIEF}

TASK — return ONLY a JSON object: {{"nodes": [...]}} — a branching dialogue graph.

Each node: {{"node_id": "n01", "speaker": "npc" | "user", "english": "...", "french_street": "...", "french_formal": "...", ...}} then EITHER "next": "nXX" (or null to end the dialogue) OR "branches": [{{"label_english": "...", "next": "nXX"}}, ...].

HARD RULES:
- nodes[0] is the opening line (usually the NPC greeting). Turns alternate npc/user.
- EVERY path from the first node to an end node (next: null) must be 12 to 28 nodes long (roughly 7-14 back-and-forth exchanges; aim for 16-22 nodes).
- Exactly 2 or 3 branch points. Branches go ON AN NPC NODE (the NPC's question creates the choice), with 2-3 options; "label_english" is the short intent the learner taps (e.g. "Ask for the wifi code"); each option's "next" is a USER node voicing that choice. Branches should reconverge after 1-2 nodes so the dialogue continues naturally.
- USER nodes: "english" = the English of the line the learner must produce (short, natural, first person — it is read aloud as the prompt); "french_street" = the natural spoken realization; "french_formal" = the full/polite written form (equal to street if nothing differs).
- NPC nodes: "french_street" = the spoken line with natural street register at native realism (fillers welcome where natural); "english" = a faithful English gloss; "french_formal" only if meaningfully different, else omit it.
- Every line short and speakable: 3-12 words. Service-French realism over completeness.
- node_ids n01, n02, ... unique; the dialogue only moves forward (no cycles); every node reachable.
- EVERY node must EXPLICITLY carry "next" or "branches" — never rely on list order. "next": null appears ONLY on the final node of a path. A node without a valid "next"/"branches" breaks the dialogue player.

Output ONLY the JSON object, no prose, no code fences."""


def structural_problems(gen):
    """Pre-remap sanity: every node explicitly linked, all refs resolve, an end
    exists. Catches the model relying on list order instead of 'next'."""
    problems = []
    ids = {n.get("node_id") for n in gen.get("nodes", [])}
    ends = 0
    for n in gen.get("nodes", []):
        nid = n.get("node_id", "?")
        if n.get("branches"):
            for b in n["branches"]:
                if b.get("next") not in ids:
                    problems.append(f"{nid}: branch next '{b.get('next')}' is not a node id")
        elif "next" in n:
            if n["next"] is None:
                ends += 1
            elif n["next"] not in ids:
                problems.append(f"{nid}: next '{n['next']}' is not a node id")
        else:
            problems.append(f"{nid}: has neither 'next' nor 'branches'")
    if not ends:
        problems.append("no end node (some node must have next: null)")
    if problems:
        return problems

    # graph-level constraints, so the retry loop enforces what the validator will
    nodes_by_id = {n["node_id"]: n for n in gen["nodes"]}
    lengths, reachable = walk_variant(nodes_by_id, gen["nodes"][0]["node_id"],
                                      problems, "graph")
    unreachable = set(nodes_by_id) - reachable
    if unreachable:
        problems.append(f"unreachable nodes: {sorted(unreachable)}")
    if lengths and not (SCN_PATH_RANGE[0] <= min(lengths)
                        and max(lengths) <= SCN_PATH_RANGE[1]):
        problems.append(f"path lengths {min(lengths)}-{max(lengths)} — every path from "
                        f"start to end must be {SCN_PATH_RANGE[0]}-{SCN_PATH_RANGE[1]} nodes")
    n_branch = sum(1 for n in gen["nodes"] if n.get("branches"))
    if not SCN_BRANCH_RANGE[0] <= n_branch <= SCN_BRANCH_RANGE[1]:
        problems.append(f"{n_branch} branch points (need "
                        f"{SCN_BRANCH_RANGE[0]}-{SCN_BRANCH_RANGE[1]})")
    return problems


def generate_variant(client, spec, k, graph, prior_lines, label, attempts=3):
    """call_claude plus a structural retry loop with corrective feedback."""
    prompt = build_prompt(spec, k, graph, prior_lines)
    for attempt in range(attempts):
        gen = call_claude(client, prompt, label=label)
        if not gen.get("nodes"):
            raise RuntimeError(f"{label}: no nodes in generation result")
        problems = structural_problems(gen)
        if not problems:
            return gen
        print(f"    structural problems (attempt {attempt + 1}): {problems[:3]}")
        prompt = build_prompt(spec, k, graph, prior_lines) + (
            "\n\nIMPORTANT — a previous attempt failed these structural checks; do not repeat them:\n"
            + "\n".join(f"- {p}" for p in problems[:10]))
    raise RuntimeError(f"{label}: structurally invalid after {attempts} attempts")


def variant_from_gen(spec, variant_no, gen):
    """Remap model node ids to globally unique ids and attach audio refs."""
    vid = f"{spec['id']}_v{variant_no}"
    uid = {n["node_id"]: f"{vid}_{n['node_id']}" for n in gen["nodes"]}

    def remap(nid):
        return uid.get(nid) if nid else None

    nodes = []
    for n in gen["nodes"]:
        node_uid = uid[n["node_id"]]
        out = {
            "node_id": node_uid,
            "speaker": n["speaker"],
            "english": n["english"].strip(),
            "french_street": n["french_street"].strip(),
        }
        formal = (n.get("french_formal") or "").strip()
        if n["speaker"] == "user":
            out["french_formal"] = formal or out["french_street"]
            out["audio_refs"] = {
                "formal": f"{node_uid}_formal.mp3",
                "street_slow": f"{node_uid}_street_slow.mp3",
                "street_fast": f"{node_uid}_street_fast.mp3",
                "english_prompt": f"{node_uid}_english.mp3",
            }
        else:
            if formal and formal != out["french_street"]:
                out["french_formal"] = formal
            out["audio_refs"] = {
                "street_fast": f"{node_uid}_street_fast.mp3",
                "street_slow": f"{node_uid}_street_slow.mp3",
            }
        if n.get("branches"):
            out["branches"] = [{"label_english": b["label_english"].strip(),
                                "next": remap(b["next"])} for b in n["branches"]]
        else:
            out["next"] = remap(n.get("next"))
        nodes.append(out)
    return {"variant_id": vid, "nodes": nodes}


def user_lines(scenario):
    return [n["french_street"] for v in scenario.get("variants", [])
            for n in v["nodes"] if n["speaker"] == "user"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", action="append", help="scenario id(s), e.g. scn_cafe")
    ap.add_argument("--variant", type=int, choices=range(1, N_VARIANTS + 1),
                    help="only this variant number")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(SPECS_PATH) as f:
        specs = json.load(f)["scenarios"]
    graph = load_v1_graph()
    out = load_output(OUT_PATH, "scenarios")
    by_id = {s["id"]: s for s in out["scenarios"]}
    client = None if args.dry_run else make_client()

    for spec in specs:
        sid = spec["id"]
        if args.scenario and sid not in args.scenario:
            continue
        scenario = by_id.get(sid)
        if scenario is None:
            scenario = {"id": sid, "title": spec["title"], "icon": spec["icon"],
                        "difficulty": spec["difficulty"],
                        "setting_blurb": spec["setting_blurb"], "variants": []}
            by_id[sid] = scenario
            out["scenarios"].append(scenario)
        have = {v["variant_id"] for v in scenario["variants"]}

        for k in range(1, N_VARIANTS + 1):
            if args.variant and k != args.variant:
                continue
            vid = f"{sid}_v{k}"
            if vid in have and not args.force:
                print(f"[skip] {vid} (exists; --force to redo)")
                continue
            print(f"[gen ] {vid}: {spec['variant_angles'][k - 1]}")
            if args.dry_run:
                print(build_prompt(spec, k, graph, user_lines(scenario)) + "\n" + "=" * 80)
                continue

            gen = generate_variant(client, spec, k, graph, user_lines(scenario), vid)
            variant = variant_from_gen(spec, k, gen)
            scenario["variants"] = [v for v in scenario["variants"]
                                    if v["variant_id"] != vid] + [variant]
            save_output(OUT_PATH, out)
            n_user = sum(1 for n in variant["nodes"] if n["speaker"] == "user")
            n_branch = sum(1 for n in variant["nodes"] if n.get("branches"))
            print(f"       {len(variant['nodes'])} nodes ({n_user} user turns, "
                  f"{n_branch} branch points) written")

    total = sum(len(s["variants"]) for s in out["scenarios"])
    print(f"\nTotal variants in {OUT_PATH.name}: {total} "
          f"across {len(out['scenarios'])} scenarios")


if __name__ == "__main__":
    main()
