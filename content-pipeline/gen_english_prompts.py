#!/usr/bin/env python3
"""English prompt audio for every drill prompt, v1 + v2 (PLAN2 §3.7).

Synthesizes {sentence_id}_english.mp3 (Google TTS en-US Standard voice — billed
on the Standard tier's separate 4M-chars/month free bucket) into
content_pack_v2/english_prompts/. This resolves the hands-free BACKFILL: with
prompt audio present, whole drill flows can run screen-off.

Sources:
    content_pack_v1/sentences.json          (v1 drill sentences)
    learn_{conjugation,vocab,grammar}.json  (v2 Learn drills; validated preferred)
    scenarios.json                          (Speak user-line intent prompts; validated
                                             preferred — enables the hands-free scenario
                                             flow of PLAN2 §5.2; branch-choice labels are
                                             excluded by design, they stay on-screen taps)

The budget estimate is always printed before any synthesis starts.

Usage:
    python gen_english_prompts.py --budget-check
    python gen_english_prompts.py
    python gen_english_prompts.py --limit 10
"""

import argparse
import json
import os
import sys
import time

from dotenv import load_dotenv

from tts import (EN_VOICE, HERE, PACK_V2, RATE_NORMAL, STANDARD_FREE_TIER,
                 load_learn, load_v2b, synthesize)

OUT_DIR = PACK_V2 / "english_prompts"


def collect_items():
    """(id, english) for every drill prompt in v1 and v2 packs."""
    items, seen = [], set()

    v1_sentences = HERE / "content_pack_v1" / "sentences.json"
    if not v1_sentences.exists():
        v1_sentences = HERE / "sentences_validated.json"
    if v1_sentences.exists():
        with open(v1_sentences) as f:
            for s in json.load(f)["sentences"]:
                items.append((s["id"], s["english"]))
        print(f"v1 source: {v1_sentences.name} ({len(items)} prompts)")
    else:
        print("WARNING: no v1 sentences file found — v1 prompts skipped")

    for module in ("conjugation", "vocab", "grammar"):
        data, src = load_learn(module)
        if data is None:
            print(f"v2 {module}: no content file yet — skipped")
            continue
        count = 0
        for node in data["nodes"]:
            for d in node.get("drills", []):
                items.append((d["id"], d["english"]))
                count += 1
        print(f"v2 source: {src} ({count} prompts)")

    scenarios = load_v2b("scenarios", "scenarios")
    if scenarios is not None:
        count = 0
        for scn in scenarios:
            for v in scn["variants"]:
                for n in v["nodes"]:
                    if n["speaker"] == "user":
                        items.append((n["node_id"], n["english"]))
                        count += 1
        print(f"v2 source: scenarios ({count} user-line prompts)")
    else:
        print("v2 scenarios: no content file yet — skipped")

    deduped = []
    for item_id, english in items:
        if item_id in seen:
            continue
        seen.add(item_id)
        deduped.append((item_id, english))
    return deduped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget-check", action="store_true", help="print budget estimate, no API calls")
    ap.add_argument("--limit", type=int, help="only synthesize the first N missing files")
    args = ap.parse_args()

    items = collect_items()
    todo = [(i, e) for i, e in items if not (OUT_DIR / f"{i}_english.mp3").exists()]
    chars = sum(len(e) for _, e in todo)
    print(f"\n=== TTS BUDGET — English prompts (en-US, Standard tier) ===")
    print(f"  {len(items)} prompts total; {len(todo)} to synthesize = {chars:,} chars")
    print(f"  Standard free tier: 4,000,000 chars/month — this run uses "
          f"{chars / STANDARD_FREE_TIER:.2%} (separate bucket from WaveNet)\n")
    if args.budget_check:
        return
    if not todo:
        print("nothing to synthesize")
        return

    load_dotenv(HERE / ".env")
    api_key = os.environ.get("GOOGLE_TTS_API_KEY")
    if not api_key:
        sys.exit("GOOGLE_TTS_API_KEY not set")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    synthesized, failures = 0, []
    for item_id, english in todo:
        if args.limit and synthesized >= args.limit:
            break
        out = OUT_DIR / f"{item_id}_english.mp3"
        try:
            out.write_bytes(synthesize(english, EN_VOICE, RATE_NORMAL, api_key))
            synthesized += 1
            if synthesized % 100 == 0:
                print(f"  {synthesized} files synthesized...")
            time.sleep(0.05)
        except RuntimeError as e:
            failures.append(f"{item_id}: {e}")
            print(f"  FAILED {item_id}: {e}", file=sys.stderr)

    print(f"done: {synthesized} synthesized, {len(failures)} failed")
    if failures:
        print(f"{len(failures)} FAILURES — rerun to retry (existing files are skipped)")
        sys.exit(1)


if __name__ == "__main__":
    main()
