#!/usr/bin/env python3
"""Batch TTS for the content pack (PLAN.md section 5).

Generates all audio with Google Cloud TTS (French WaveNet) for now:
  {id}_formal.mp3       — french_formal, natural rate
  {id}_street_slow.mp3  — french_street, slowed for shadowing
  {id}_street_fast.mp3  — french_street, faster rate (native-speed feel)

BACKFILL: street variants (street_slow, street_fast) are to be regenerated
with ElevenLabs for authentic casual prosody once the $5 sub is active —
WaveNet reads street reductions in a formal voice. The file naming stays
identical, so regeneration is a drop-in replacement.

Also synthesizes audio for every canonical example in graph.json
({node_id}_ex{NN}_*.mp3) and assembles content_pack_v1/ (graph.json +
sentences.json + audio/).

Usage:
    python tts_batch.py --dry-run     # count characters, no API calls
    python tts_batch.py               # full run (skips existing files)
    python tts_batch.py --limit 5     # first 5 items only (smoke test)
"""

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

from tts import FR_VOICE, synthesize as tts_synthesize

HERE = Path(__file__).parent
PACK_DIR = HERE / "content_pack_v1"
AUDIO_DIR = PACK_DIR / "audio"

# variant -> (text field, speaking rate)
VARIANTS = {
    "formal": ("french_formal", 1.0),
    "street_slow": ("french_street", 0.8),
    "street_fast": ("french_street", 1.25),  # BACKFILL: regenerate with ElevenLabs
}


def synthesize(text, rate, api_key):
    # shared implementation lives in tts.py (v2 refactor); same voice, same retries
    return tts_synthesize(text, FR_VOICE, rate, api_key)


def collect_items():
    """Yield (item_id, {'french_formal': ..., 'french_street': ...}) for every
    drill sentence and every canonical example."""
    items = []

    sentences_path = HERE / "sentences_validated.json"
    if not sentences_path.exists():
        sentences_path = HERE / "sentences.json"
    if sentences_path.exists():
        with open(sentences_path) as f:
            for s in json.load(f)["sentences"]:
                items.append((s["id"], s))
        print(f"sentences source: {sentences_path.name}")
    else:
        print("no sentences file found — canonical examples only")

    with open(HERE / "graph.json") as f:
        graph = json.load(f)
    for node in graph["nodes"]:
        for i, ex in enumerate(node["canonical_examples"], 1):
            items.append(
                (f"{node['id']}_ex{i:02d}",
                 {"french_formal": ex["formal"], "french_street": ex["street"]})
            )
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="count chars, no API calls")
    ap.add_argument("--limit", type=int, help="only process the first N items")
    args = ap.parse_args()

    load_dotenv(HERE / ".env")
    api_key = os.environ.get("GOOGLE_TTS_API_KEY")
    if not api_key and not args.dry_run:
        sys.exit("GOOGLE_TTS_API_KEY not set — copy .env.example to .env and add your key")

    items = collect_items()
    if args.limit:
        items = items[: args.limit]

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)

    total_chars, synthesized, skipped, failures = 0, 0, 0, []
    for item_id, item in items:
        for variant, (field, rate) in VARIANTS.items():
            text = item[field]
            out = AUDIO_DIR / f"{item_id}_{variant}.mp3"
            if out.exists():
                skipped += 1
                continue
            total_chars += len(text)
            if args.dry_run:
                continue
            try:
                audio = synthesize(text, rate, api_key)
            except RuntimeError as e:
                failures.append(f"{item_id}_{variant}: {e}")
                print(f"  FAILED {item_id}_{variant}: {e}", file=sys.stderr)
                continue
            out.write_bytes(audio)
            synthesized += 1
            if synthesized % 50 == 0:
                print(f"  {synthesized} files synthesized...")
            time.sleep(0.05)  # stay polite with the API

    if args.dry_run:
        print(f"DRY RUN: {len(items)} items, {total_chars:,} chars to synthesize "
              f"({skipped} files already exist)")
        print(f"WaveNet free tier is 1,000,000 chars/month — this uses "
              f"{total_chars / 1_000_000:.1%} of it")
        return

    # assemble the pack
    shutil.copy(HERE / "graph.json", PACK_DIR / "graph.json")
    src = HERE / "sentences_validated.json"
    if src.exists():
        shutil.copy(src, PACK_DIR / "sentences.json")
    elif (HERE / "sentences.json").exists():
        shutil.copy(HERE / "sentences.json", PACK_DIR / "sentences.json")

    print(f"done: {synthesized} files synthesized, {skipped} skipped (existing), "
          f"{len(failures)} failed, {total_chars:,} chars used")
    print(f"content pack assembled at {PACK_DIR}/")
    print("BACKFILL reminder: regenerate *_street_slow.mp3 and *_street_fast.mp3 "
          "with ElevenLabs for authentic street prosody.")
    if failures:
        print(f"{len(failures)} FAILURES — rerun to retry (existing files are skipped)")
        sys.exit(1)


if __name__ == "__main__":
    main()
