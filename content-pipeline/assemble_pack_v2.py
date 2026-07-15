#!/usr/bin/env python3
"""Assemble content_pack_v2 (PLAN2 §3.7, phase 7).

Three steps:
1. Copy each module's validated JSON into the pack under its shipping name:
     learn_conjugation_validated.json -> learn/conjugation.json
     learn_vocab_validated.json       -> learn/vocab.json
     learn_grammar_validated.json     -> learn/grammar.json
     scenarios_validated.json         -> speak/scenarios.json
     listen_validated.json            -> listen/episodes.json
     read_validated.json              -> read/passages.json
2. Verify audio completeness: every file the pack content references must
   exist on disk. Expected files are enumerated with the same job builders
   tts.py synthesizes from (plus gen_english_prompts' item list), so the
   naming logic lives in exactly one place. Orphan/zero-byte mp3s are flagged.
3. Write manifest.json at the pack root: pack version, build timestamp, full
   content inventory (unit/drill/line/question counts per module) and audio
   file counts.

Usage:
    python assemble_pack_v2.py            # copy + verify + write manifest
    python assemble_pack_v2.py --dry-run  # verify + print inventory, write nothing

Exits 1 if any referenced audio file is missing or empty.
"""

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone

from gen_english_prompts import OUT_DIR as EN_AUDIO
from gen_english_prompts import collect_items
from tts import (HERE, LEARN_AUDIO, LISTEN_AUDIO, PACK_V2, SPEAK_AUDIO,
                 collect_jobs, collect_listen_jobs, collect_speak_jobs)

COPIES = [
    ("learn_conjugation_validated.json", "learn/conjugation.json"),
    ("learn_vocab_validated.json", "learn/vocab.json"),
    ("learn_grammar_validated.json", "learn/grammar.json"),
    ("scenarios_validated.json", "speak/scenarios.json"),
    ("listen_validated.json", "listen/episodes.json"),
    ("read_validated.json", "read/passages.json"),
]


def copy_sources(dry_run):
    copied, absent = [], []
    for src_name, dest_rel in COPIES:
        src = HERE / src_name
        if not src.exists():
            absent.append(src_name)
            continue
        if not dry_run:
            dest = PACK_V2 / dest_rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
        copied.append(dest_rel)
    return copied, absent


def load_pack(rel):
    path = PACK_V2 / rel
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def learn_inventory():
    inv = {}
    for module, rel in (("conjugation", "learn/conjugation.json"),
                        ("vocab", "learn/vocab.json"),
                        ("grammar", "learn/grammar.json")):
        data = load_pack(rel)
        if data is None:
            inv[module] = None
            continue
        nodes = data["nodes"]
        entry = {"nodes": len(nodes),
                 "drills": sum(len(n.get("drills", [])) for n in nodes)}
        if module == "conjugation":
            entry["verbs"] = sum(1 for n in nodes if n.get("family") != "politesse")
        elif module == "vocab":
            entry["words"] = sum(len(n.get("words", [])) for n in nodes)
        elif module == "grammar":
            entry["canonical_examples"] = sum(len(n.get("canonical_examples", []))
                                              for n in nodes)
        inv[module] = entry
    return inv


def speak_inventory():
    data = load_pack("speak/scenarios.json")
    if data is None:
        return None
    scenarios = data["scenarios"]
    nodes = user_turns = branch_points = 0
    for scn in scenarios:
        for v in scn["variants"]:
            for n in v["nodes"]:
                nodes += 1
                user_turns += n["speaker"] == "user"
                branch_points += bool(n.get("branches"))
    return {"scenarios": len(scenarios),
            "variants": sum(len(s["variants"]) for s in scenarios),
            "dialogue_nodes": nodes, "user_turns": user_turns,
            "branch_points": branch_points}


def listen_inventory():
    data = load_pack("listen/episodes.json")
    if data is None:
        return None
    episodes = data["episodes"]
    by_level = {}
    for ep in episodes:
        by_level[ep["level"]] = by_level.get(ep["level"], 0) + 1
    return {"episodes": len(episodes), "by_level": dict(sorted(by_level.items())),
            "lines": sum(len(ep["lines"]) for ep in episodes),
            "questions": sum(len(ep["questions"]) for ep in episodes),
            "est_fast_audio_sec": sum(ep["est_duration_sec"] for ep in episodes)}


def read_inventory():
    data = load_pack("read/passages.json")
    if data is None:
        return None
    passages = data["passages"]
    by_style, by_tier = {}, {}
    for p in passages:
        by_style[p["style"]] = by_style.get(p["style"], 0) + 1
        by_tier[str(p["tier"])] = by_tier.get(str(p["tier"]), 0) + 1
    return {"passages": len(passages),
            "by_style": dict(sorted(by_style.items())),
            "by_tier": dict(sorted(by_tier.items())),
            "words": sum(p["word_count"] for p in passages),
            "gloss_entries": sum(len(p["gloss"]) for p in passages),
            "questions": sum(len(p["questions"]) for p in passages)}


def expected_audio():
    """Every audio file the pack references, per audio dir — from the same
    collectors tts.py synthesizes from."""
    jobs, _ = collect_jobs(["conjugation", "vocab", "grammar"])
    learn = {p for _, p, *_ in jobs}
    speak_jobs, _ = collect_speak_jobs()
    speak = {p for _, p, *_ in speak_jobs}
    listen_jobs, episodes = collect_listen_jobs()
    listen = {p for _, p, *_ in listen_jobs}
    for ep in episodes:
        for speed in ("fast", "slow"):
            listen.add(LISTEN_AUDIO / ep["audio_refs"][f"full_{speed}"])
    listen.add(LISTEN_AUDIO / "_gap.mp3")  # concat spacer, kept for reassembly
    english = {EN_AUDIO / f"{item_id}_english.mp3" for item_id, _ in collect_items()}
    return {"learn": (LEARN_AUDIO, learn), "speak": (SPEAK_AUDIO, speak),
            "listen": (LISTEN_AUDIO, listen), "english_prompts": (EN_AUDIO, english)}


def verify_audio():
    report = {}
    for name, (audio_dir, expected) in expected_audio().items():
        actual = set(audio_dir.glob("*.mp3")) if audio_dir.exists() else set()
        report[name] = {
            "files": len(actual),
            "bytes": sum(p.stat().st_size for p in actual),
            "expected": len(expected),
            "missing": sorted(p.name for p in expected - actual),
            "orphans": sorted(p.name for p in actual - expected),
            "empty": sorted(p.name for p in actual if p.stat().st_size == 0),
        }
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="verify and print the inventory without writing anything")
    args = ap.parse_args()

    copied, absent = copy_sources(args.dry_run)
    verb = "would copy" if args.dry_run else "copied"
    for rel in copied:
        print(f"{verb}: {rel}")
    for name in absent:
        print(f"MISSING SOURCE: {name} — module left out of the pack")

    content = {"learn": learn_inventory(), "speak": speak_inventory(),
               "listen": listen_inventory(), "read": read_inventory()}
    print("\n=== CONTENT INVENTORY ===")
    print(json.dumps(content, indent=2, ensure_ascii=False))

    print("\n=== AUDIO ===")
    audio = verify_audio()
    problems = 0
    for name, r in audio.items():
        line = (f"  {name:16s} {r['files']:>6,} files ({r['bytes'] / 1e6:,.0f} MB), "
                f"{r['expected']:,} referenced")
        for kind in ("missing", "empty", "orphans"):
            if r[kind]:
                line += f", {len(r[kind])} {kind.upper() if kind != 'orphans' else 'orphans'}"
                if kind != "orphans":
                    problems += len(r[kind])
        print(line)
        for kind in ("missing", "empty"):
            for fname in r[kind][:5]:
                print(f"    {kind}: {fname}")
        if r["orphans"]:
            print(f"    orphans (on disk, unreferenced): {r['orphans'][:5]}"
                  + (" ..." if len(r["orphans"]) > 5 else ""))

    manifest = {
        "pack_version": 2,
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "content": content,
        "audio": {name: {"files": r["files"], "bytes": r["bytes"],
                         "missing": len(r["missing"]), "orphans": len(r["orphans"])}
                  for name, r in audio.items()},
        "notes": {
            "read_audio": "none by design — passage TTS deferred (PLAN2 §3.6)",
            "street_audio": "BACKFILL: regenerate street variants with ElevenLabs",
            "generation_model": "claude-sonnet-4-6",
            "tts": "Google WaveNet fr-FR (French); Standard en-US (English prompts)",
        },
    }
    if args.dry_run:
        print("\n--dry-run: manifest not written")
    else:
        out = PACK_V2 / "manifest.json"
        with open(out, "w") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        print(f"\nwrote {out.relative_to(HERE)}")

    if problems:
        sys.exit(f"{problems} referenced audio file(s) missing or empty — "
                 f"run tts.py / gen_english_prompts.py, then reassemble")
    print("audio complete: every referenced file present and non-empty")


if __name__ == "__main__":
    main()
