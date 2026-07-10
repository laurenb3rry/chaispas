#!/usr/bin/env python3
"""Generate the Learn/Vocabulary module (PLAN2 §3.2).

Takes the ranked lemma list (data/freq_fr_1000.txt), removes words already
taught by v1 concepts and the conjugation module, and slices the top 1,000
survivors into 40 packs x 25 words, frequency-ordered. Each pack becomes a
ConceptNode of type `vocab_pack`. Per pack, Claude glosses the words and writes
~28 drill sentences (formal + street + English) so every word appears in >= 2
sentences — vocabulary is never drilled as bare word lists. Grammar is
best-effort constrained to the v1 spine (the validator warns rather than
rejects, per plan).

Output: learn_vocab.json

Usage:
    python gen_vocab.py                 # all 40 packs
    python gen_vocab.py --pack 1        # single pack
    python gen_vocab.py --dry-run       # print prompt for the first requested pack
"""

import argparse
import json

from genlib import (HERE, STREET_REGISTER_BRIEF, call_claude, load_output,
                    load_v1_graph, make_client, save_output, v1_concept_summaries)
from validate import FUNCTION_WORDS, lemma_in_text, tokenize

FREQ_PATH = HERE / "data" / "freq_fr_1000.txt"
VERBS_PATH = HERE / "data" / "verbs.json"
OUT_PATH = HERE / "learn_vocab.json"

N_PACKS = 40
PACK_SIZE = 25
N_SENTENCES = 28  # ~2 target words each -> every word covered >= 2 times


def taught_words():
    """Words the learner already has: v1 canonical examples + conjugation verbs
    + closed-class function words."""
    words = set(FUNCTION_WORDS)
    for node in load_v1_graph()["nodes"]:
        for ex in node["canonical_examples"]:
            words.update(tokenize(ex["formal"]))
            words.update(tokenize(ex["street"]))
    with open(VERBS_PATH) as f:
        vdata = json.load(f)
    for verb in vdata["verbs"]:
        words.add(verb["infinitive"])
        words.add(verb["participle"])
        words.update(verb["present"].values())
    return words


def load_packs():
    lemmas = [l.strip() for l in open(FREQ_PATH, encoding="utf-8")
              if l.strip() and not l.startswith("#")]
    taught = taught_words()
    kept = [l for l in lemmas if l not in taught]
    dropped = len(lemmas) - len(kept)
    if len(kept) < N_PACKS * PACK_SIZE:
        raise SystemExit(f"only {len(kept)} lemmas after dedupe ({dropped} dropped) — "
                         f"need {N_PACKS * PACK_SIZE}; extend data/freq_fr_1000.txt")
    print(f"freq list: {len(lemmas)} lemmas, {dropped} already taught, using top {N_PACKS * PACK_SIZE}")
    kept = kept[: N_PACKS * PACK_SIZE]
    return [kept[i * PACK_SIZE:(i + 1) * PACK_SIZE] for i in range(N_PACKS)]


def build_prompt(pack_no, words, graph, n_sentences=N_SENTENCES, only_words=None):
    focus = ""
    if only_words:
        focus = (f"\nIMPORTANT: this is a top-up call. Every sentence must target one of "
                 f"these under-covered words: {', '.join(only_words)}.")
    return f"""You are writing vocabulary pack {pack_no} for "Chais Pas", a Michel Thomas-style spoken-French course with a first-class street-register layer. The learner knows the v1 curriculum below. Vocabulary is NEVER drilled as bare word lists — every word is learned inside sentences.

THE {len(words)} PACK WORDS (French lemmas, ranked by spoken frequency):
{', '.join(words)}

V1 CURRICULUM (the grammar the learner has — build sentences from these constructions where feasible):
{v1_concept_summaries(graph)}

{STREET_REGISTER_BRIEF}

TASK — return a JSON object with two keys:

1. "words": one entry per pack word, in the order given: {{"lemma": "...", "english": "concise gloss", "pos": "noun|verb|adj|adv|expr", "note": "article for nouns (le/la), one-line usage hint — omit if nothing useful"}}

2. "sentences": exactly {n_sentences} drill sentences. Requirements:
   - each sentence showcases 1-2 pack words in natural use; across the set, EVERY pack word appears in at least 2 sentences (inflected forms count){focus}
   - grammar stays inside the v1 curriculum above where feasible: c'est, vouloir/pouvoir/devoir, aller, futur proche, passé composé, simple questions — short spoken French, 3-10 words
   - everyday-France content: café, shops, métro, friends, plans, reactions
   - each: {{"english": "...", "french_formal": "...", "french_street": "...", "target_words": ["lemma", ...], "concept_ids": [v1 concept ids actually used]}}
   - target_words lists the pack words the sentence exercises (their lemma form as given above)
   - french_street applies the street rules; no invented slang
   - no duplicates, no near-duplicates

Output ONLY the JSON object, no prose, no code fences."""


def coverage(words, sentences):
    counts = {w: 0 for w in words}
    for s in sentences:
        toks = set(tokenize(s["french_formal"])) | set(tokenize(s["french_street"]))
        for w in words:
            if lemma_in_text(w, toks):
                counts[w] += 1
    return counts


def gen_pack(client, pack_no, words, graph):
    gen = call_claude(client, build_prompt(pack_no, words, graph), label=f"pack {pack_no}")
    glosses, sentences = gen.get("words", []), gen.get("sentences", [])
    if len(glosses) != len(words):
        raise RuntimeError(f"pack {pack_no}: expected {len(words)} glosses, got {len(glosses)}")

    counts = coverage(words, sentences)
    uncovered = [w for w, c in counts.items() if c < 2]
    if uncovered:
        print(f"       top-up for {len(uncovered)} under-covered words: {uncovered}")
        extra = call_claude(
            client,
            build_prompt(pack_no, words, graph,
                         n_sentences=max(4, 2 * len(uncovered)), only_words=uncovered),
            label=f"pack {pack_no} top-up")
        sentences += extra.get("sentences", [])
        counts = coverage(words, sentences)
        still = [w for w, c in counts.items() if c < 2]
        if still:
            print(f"       WARNING: still under-covered after top-up: {still} "
                  f"(validator will flag)")
    return glosses, sentences


def node_for_pack(pack_no, rank_start, glosses, sentences):
    nid = f"vocab_pack_{pack_no:02d}"
    tier = min(3, (pack_no - 1) // 10)
    words = []
    for j, g in enumerate(glosses, 1):
        w = {"id": f"{nid}_w{j:02d}", "lemma": g["lemma"].strip(),
             "english": g["english"].strip(), "pos": g.get("pos", "")}
        if g.get("note"):
            w["note"] = g["note"].strip()
        words.append(w)
    drills = []
    for i, s in enumerate(sentences, 1):
        drills.append({
            "id": f"{nid}_{i:03d}",
            "target_concept_id": nid,
            "concept_ids": sorted(set(s.get("concept_ids", [])) | {nid}),
            "target_words": s.get("target_words", []),
            "english": s["english"].strip(),
            "french_formal": s["french_formal"].strip(),
            "french_street": s["french_street"].strip(),
        })
    return {
        "id": nid,
        "type": "vocab_pack",
        "tier": tier,
        "prereq_ids": [],
        "title": f"Vocabulary {pack_no} · words {rank_start}–{rank_start + PACK_SIZE - 1}",
        "words": words,
        "drills": drills,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", type=int, action="append", help="pack number(s) 1-40")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    packs = load_packs()
    graph = load_v1_graph()
    out = load_output(OUT_PATH, "nodes")
    done = {n["id"] for n in out["nodes"]}
    client = None if args.dry_run else make_client()

    for pack_no in range(1, N_PACKS + 1):
        if args.pack and pack_no not in args.pack:
            continue
        nid = f"vocab_pack_{pack_no:02d}"
        if nid in done and not args.force:
            print(f"[skip] {nid} (exists; --force to redo)")
            continue
        words = packs[pack_no - 1]
        print(f"[gen ] {nid}: {', '.join(words[:6])} ...")
        if args.dry_run:
            print(build_prompt(pack_no, words, graph) + "\n" + "=" * 80)
            break

        glosses, sentences = gen_pack(client, pack_no, words, graph)
        node = node_for_pack(pack_no, (pack_no - 1) * PACK_SIZE + 1, glosses, sentences)
        out["nodes"] = [n for n in out["nodes"] if n["id"] != nid] + [node]
        save_output(OUT_PATH, out)
        print(f"       {len(node['words'])} words, {len(node['drills'])} sentences written")

    print(f"\nTotal vocab packs in {OUT_PATH.name}: {len(out['nodes'])}")


if __name__ == "__main__":
    main()
