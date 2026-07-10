#!/usr/bin/env python3
"""Shared TTS library + v2 content synthesis CLI (PLAN2 §3.7).

Library (used by tts_batch.py and gen_english_prompts.py):
    synthesize(text, voice, rate, api_key)  — Google Cloud TTS with retries
    budget_report(...)                      — free-tier accounting

CLI — synthesizes all French audio for the v2 pack:
  Learn (content_pack_v2/learn/audio/, from learn_*.json, validated preferred):
    conjugation tables   {node}_tbl_{tense}_{person}_{formal|street}.mp3   (street only where it differs)
    politesse forms      {node}_{form_id}_{formal|street}.mp3
    vocab words          {word_id}.mp3
    grammar examples     {node}_ex{NN}_{formal|street_slow|street_fast}.mp3
    all drills           {id}_{formal|street_slow|street_fast}.mp3
  Speak (content_pack_v2/speak/audio/, from scenarios.json, validated preferred):
    npc lines            {node_uid}_{street_fast|street_slow}.mp3
    user lines           {node_uid}_{formal|street_slow|street_fast}.mp3
  Listen (content_pack_v2/listen/audio/, from listen.json, validated preferred):
    per line             {line_id}_{fast|slow}.mp3   (two WaveNet voices per episode,
                                                      per-episode level rates)
    full episode         {episode_id}_full_{fast|slow}.mp3 — assembled locally by
                         concatenating the line MP3s with a synthesized 500ms gap
                         (same encoder params throughout, so raw concat is safe)

The budget estimate is ALWAYS printed before any synthesis starts; a real run
also requires the printed estimate to fit the remaining WaveNet free tier or
--ignore-budget. English prompt audio (incl. Speak user prompts) lives in
gen_english_prompts.py on the separate Standard tier.

BACKFILL (carried from v1): street variants to be regenerated with ElevenLabs
for authentic casual prosody — file naming is drop-in identical.

Usage:
    python tts.py --budget-check        # dry run: chars + free-tier % + full-run projection
    python tts.py                       # synthesize everything missing
    python tts.py --module scenarios --module listen
    python tts.py --module conjugation --limit 20
"""

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

HERE = Path(__file__).parent
PACK_V2 = HERE / "content_pack_v2"
LEARN_AUDIO = PACK_V2 / "learn" / "audio"
SPEAK_AUDIO = PACK_V2 / "speak" / "audio"
LISTEN_AUDIO = PACK_V2 / "listen" / "audio"

TTS_URL = "https://texttospeech.googleapis.com/v1/text:synthesize"
FR_VOICE = {"languageCode": "fr-FR", "name": "fr-FR-Wavenet-C"}  # same voice as pack v1
EN_VOICE = {"languageCode": "en-US", "name": "en-US-Standard-C"}  # standard tier: separate 4M free bucket

WAVENET_FREE_TIER = 1_000_000  # chars/month
STANDARD_FREE_TIER = 4_000_000

RATE_NORMAL, RATE_SLOW, RATE_FAST = 1.0, 0.8, 1.25
TENSES = ["present", "passe_compose", "imparfait", "futur_proche"]
PERSONS = ["je", "tu", "il", "on", "vous", "ils"]

# Expected unit counts for the full-run projection printed by --budget-check.
# scenarios counts variants (12 scenarios x 3); listen counts episodes.
EXPECTED_UNITS = {"conjugation": 21, "vocab": 40, "grammar": 15,
                  "scenarios": 36, "listen": 30}
GAP_MS = 500  # silence between lines in assembled full-episode audio


def synthesize(text, voice, rate, api_key, ssml=False):
    body = {
        "input": {"ssml": text} if ssml else {"text": text},
        "voice": voice,
        "audioConfig": {"audioEncoding": "MP3", "speakingRate": rate},
    }
    for attempt in range(5):
        try:
            resp = requests.post(TTS_URL, params={"key": api_key}, json=body, timeout=30)
        except requests.RequestException as e:
            wait = 2 ** (attempt + 1)
            print(f"    network error ({type(e).__name__}), retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        if resp.status_code == 200:
            return base64.b64decode(resp.json()["audioContent"])
        # 403 included: key-restriction changes flap for ~5 min while propagating
        if resp.status_code in (403, 429) or resp.status_code >= 500:
            wait = 30 * (attempt + 1) if resp.status_code == 403 else 2 ** (attempt + 1)
            print(f"    HTTP {resp.status_code}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        raise RuntimeError(f"TTS failed ({resp.status_code}): {resp.text[:200]}")
    raise RuntimeError("TTS failed after retries")


def load_learn(module):
    """Prefer the validated file; fall back to the raw generator output."""
    validated = HERE / f"learn_{module}_validated.json"
    raw = HERE / f"learn_{module}.json"
    path = validated if validated.exists() else raw
    if not path.exists():
        return None, None
    if path is raw:
        print(f"  note: {validated.name} not found — using unvalidated {raw.name}")
    with open(path) as f:
        return json.load(f), path.name


def drill_jobs(node, out_dir):
    for d in node.get("drills", []):
        yield (out_dir / f"{d['id']}_formal.mp3", d["french_formal"], FR_VOICE, RATE_NORMAL)
        yield (out_dir / f"{d['id']}_street_slow.mp3", d["french_street"], FR_VOICE, RATE_SLOW)
        yield (out_dir / f"{d['id']}_street_fast.mp3", d["french_street"], FR_VOICE, RATE_FAST)


def collect_jobs(modules):
    """Yield (module, out_path, text, voice, rate). Skips missing content files."""
    jobs, found = [], {}
    for module in modules:
        data, src = load_learn(module)
        if data is None:
            print(f"  {module}: no content file yet — skipped")
            continue
        found[module] = len(data["nodes"])
        for node in data["nodes"]:
            if module == "conjugation":
                for tense in TENSES:
                    for person, cell in node.get("table", {}).get(tense, {}).items():
                        base = LEARN_AUDIO / f"{node['id']}_tbl_{tense}_{person}"
                        jobs.append((module, Path(f"{base}_formal.mp3"), cell["formal"], FR_VOICE, RATE_NORMAL))
                        if "street" in cell:
                            jobs.append((module, Path(f"{base}_street.mp3"), cell["street"], FR_VOICE, RATE_NORMAL))
                for form in node.get("forms", []):  # politesse mini-module
                    base = LEARN_AUDIO / f"{node['id']}_{form['id']}"
                    jobs.append((module, Path(f"{base}_formal.mp3"), form["formal"], FR_VOICE, RATE_NORMAL))
                    if form["street"] != form["formal"]:
                        jobs.append((module, Path(f"{base}_street.mp3"), form["street"], FR_VOICE, RATE_NORMAL))
            elif module == "vocab":
                for w in node.get("words", []):
                    jobs.append((module, LEARN_AUDIO / f"{w['id']}.mp3", w["lemma"], FR_VOICE, RATE_NORMAL))
            elif module == "grammar":
                for i, ex in enumerate(node.get("canonical_examples", []), 1):
                    base = LEARN_AUDIO / f"{node['id']}_ex{i:02d}"
                    jobs.append((module, Path(f"{base}_formal.mp3"), ex["formal"], FR_VOICE, RATE_NORMAL))
                    jobs.append((module, Path(f"{base}_street_slow.mp3"), ex["street"], FR_VOICE, RATE_SLOW))
                    jobs.append((module, Path(f"{base}_street_fast.mp3"), ex["street"], FR_VOICE, RATE_FAST))
            for j in drill_jobs(node, LEARN_AUDIO):
                jobs.append((module,) + j)
    return jobs, found


def load_v2b(name, key):
    """scenarios/listen content; validated file preferred, like load_learn."""
    validated = HERE / f"{name}_validated.json"
    raw = HERE / f"{name}.json"
    path = validated if validated.exists() else raw
    if not path.exists():
        return None
    if path is raw:
        print(f"  note: {validated.name} not found — using unvalidated {raw.name}")
    with open(path) as f:
        return json.load(f)[key]


def collect_speak_jobs():
    """(module, out_path, text, voice, rate) for every scenario line. Returns
    (jobs, n_variants) — n_variants feeds the full-run projection."""
    scenarios = load_v2b("scenarios", "scenarios")
    if scenarios is None:
        print("  scenarios: no content file yet — skipped")
        return [], 0
    jobs, n_variants = [], 0
    for scn in scenarios:
        for v in scn["variants"]:
            n_variants += 1
            for n in v["nodes"]:
                uid, street = n["node_id"], n["french_street"]
                if n["speaker"] == "user":
                    formal = n.get("french_formal", street)
                    jobs.append(("scenarios", SPEAK_AUDIO / f"{uid}_formal.mp3", formal, FR_VOICE, RATE_NORMAL))
                    jobs.append(("scenarios", SPEAK_AUDIO / f"{uid}_street_slow.mp3", street, FR_VOICE, RATE_SLOW))
                    jobs.append(("scenarios", SPEAK_AUDIO / f"{uid}_street_fast.mp3", street, FR_VOICE, RATE_FAST))
                else:
                    jobs.append(("scenarios", SPEAK_AUDIO / f"{uid}_street_fast.mp3", street, FR_VOICE, RATE_FAST))
                    jobs.append(("scenarios", SPEAK_AUDIO / f"{uid}_street_slow.mp3", street, FR_VOICE, RATE_SLOW))
    return jobs, n_variants


def collect_listen_jobs():
    """Per-line jobs, two voices per episode at the episode's level rates.
    Returns (jobs, episodes) — episodes are needed again for concat."""
    episodes = load_v2b("listen", "episodes")
    if episodes is None:
        print("  listen: no content file yet — skipped")
        return [], []
    jobs = []
    for ep in episodes:
        voices = {i + 1: {"languageCode": "fr-FR", "name": s["voice"]}
                  for i, s in enumerate(ep["speakers"])}
        for l in ep["lines"]:
            voice = voices[l["speaker"]]
            jobs.append(("listen", LISTEN_AUDIO / l["audio_refs"]["fast"],
                         l["french_street"], voice, ep["rate_fast"]))
            jobs.append(("listen", LISTEN_AUDIO / l["audio_refs"]["slow"],
                         l["french_street"], voice, ep["rate_slow"]))
    return jobs, episodes


def listen_spec_projection():
    """Char estimate for the full 30-episode run from the spec file alone
    (level char-target midpoints x 2 renditions) — level-mix aware, unlike the
    linear per-unit projection."""
    from gen_listen import LEVELS
    spec_path = HERE / "data" / "listen_episodes.json"
    if not spec_path.exists():
        return None
    with open(spec_path) as f:
        specs = json.load(f)["episodes"]
    return sum(sum(LEVELS[s["level"]]["chars"]) for s in specs)  # midpoint x 2 = sum


def assemble_full_episodes(episodes, api_key):
    """Build {ep}_full_fast/slow.mp3 by concatenating line MP3s with a
    synthesized silence gap. Google returns uniform CBR MP3 frames, so raw
    byte concatenation is safe."""
    gap_path = LISTEN_AUDIO / "_gap.mp3"
    if not gap_path.exists():
        LISTEN_AUDIO.mkdir(parents=True, exist_ok=True)
        gap_path.write_bytes(synthesize(
            f'<speak><break time="{GAP_MS}ms"/></speak>',
            FR_VOICE, RATE_NORMAL, api_key, ssml=True))
    gap = gap_path.read_bytes()
    built, waiting = 0, 0
    for ep in episodes:
        for speed in ("fast", "slow"):
            out = LISTEN_AUDIO / ep["audio_refs"][f"full_{speed}"]
            if out.exists():
                continue
            parts = [LISTEN_AUDIO / l["audio_refs"][speed] for l in ep["lines"]]
            if not all(p.exists() for p in parts):
                waiting += 1
                continue
            chunks = []
            for i, p in enumerate(parts):
                if i:
                    chunks.append(gap)
                chunks.append(p.read_bytes())
            out.write_bytes(b"".join(chunks))
            built += 1
    print(f"full episodes: {built} assembled"
          + (f", {waiting} waiting on missing line files" if waiting else ""))


def budget_report(jobs, found, label="v2 French audio (WaveNet)"):
    """Print the budget estimate. Returns chars still to synthesize."""
    todo = [(m, p, t) for m, p, t, *_ in jobs if not p.exists()]
    todo_chars = sum(len(t) for _, _, t in todo)
    done = len(jobs) - len(todo)
    per_module = {}
    for m, _, t in todo:
        per_module[m] = per_module.get(m, 0) + len(t)

    print(f"\n=== TTS BUDGET — {label} ===")
    for m, chars in sorted(per_module.items()):
        n_units = found.get(m, 0)
        line = f"  {m:12s} {chars:>9,} chars ({n_units} unit(s) present"
        expected = EXPECTED_UNITS.get(m)
        if expected and 0 < n_units < expected:
            projected = chars * expected / n_units
            line += f"; full {expected}-unit projection ≈ {projected:,.0f} chars"
        print(line + ")")
    print(f"  {'TOTAL':12s} {todo_chars:>9,} chars to synthesize "
          f"({len(todo)} files; {done} already exist)")
    print(f"  WaveNet free tier: 1,000,000 chars/month — this run uses {todo_chars / WAVENET_FREE_TIER:.1%}")
    if any(0 < found.get(m, 0) < EXPECTED_UNITS.get(m, 0) for m in found):
        projection = sum(per_module.get(m, 0) * EXPECTED_UNITS.get(m, n) / n
                         for m, n in found.items() if n)
        units = " + ".join(f"{EXPECTED_UNITS[m]} {m}" for m in sorted(found)
                           if m in EXPECTED_UNITS)
        print(f"  Full-run projection ({units} units; scenarios counted in variants): "
              f"≈ {projection:,.0f} chars ≈ {projection / WAVENET_FREE_TIER:.1%} of the free tier")
    if "listen" in found:
        spec_est = listen_spec_projection()
        if spec_est:
            print(f"  Listen spec-based full-run estimate (level-mix aware, 30 episodes, "
                  f"fast+slow): ≈ {spec_est:,.0f} chars ≈ {spec_est / WAVENET_FREE_TIER:.1%}")
    print(f"  (English prompt audio is billed on the separate Standard tier — "
          f"see gen_english_prompts.py --budget-check)\n")
    return todo_chars


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget-check", action="store_true", help="print budget estimate, no API calls")
    ap.add_argument("--module", action="append",
                    choices=["conjugation", "vocab", "grammar", "scenarios", "listen"])
    ap.add_argument("--limit", type=int, help="only synthesize the first N missing files")
    ap.add_argument("--ignore-budget", action="store_true",
                    help="proceed even if the run exceeds the monthly free tier")
    args = ap.parse_args()

    modules = args.module or ["conjugation", "vocab", "grammar", "scenarios", "listen"]
    jobs, found = collect_jobs([m for m in modules
                                if m in ("conjugation", "vocab", "grammar")])
    episodes = []
    if "scenarios" in modules:
        speak_jobs, n_variants = collect_speak_jobs()
        jobs += speak_jobs
        if n_variants:
            found["scenarios"] = n_variants
    if "listen" in modules:
        line_jobs, episodes = collect_listen_jobs()
        jobs += line_jobs
        if episodes:
            found["listen"] = len(episodes)

    todo_chars = budget_report(jobs, found)
    if args.budget_check:
        return
    need_concat = any(not (LISTEN_AUDIO / ep["audio_refs"][f"full_{speed}"]).exists()
                      for ep in episodes for speed in ("fast", "slow"))
    if todo_chars == 0 and not need_concat:
        print("nothing to synthesize")
        return
    if todo_chars > WAVENET_FREE_TIER and not args.ignore_budget:
        sys.exit("run exceeds the monthly WaveNet free tier — split across a month "
                 "boundary or pass --ignore-budget")

    load_dotenv(HERE / ".env")
    api_key = os.environ.get("GOOGLE_TTS_API_KEY")
    if not api_key:
        sys.exit("GOOGLE_TTS_API_KEY not set")

    synthesized, failures = 0, []
    for module, out, text, voice, rate in jobs:
        if out.exists():
            continue
        if args.limit and synthesized >= args.limit:
            break
        try:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(synthesize(text, voice, rate, api_key))
            synthesized += 1
            if synthesized % 50 == 0:
                print(f"  {synthesized} files synthesized...")
            time.sleep(0.05)
        except RuntimeError as e:
            failures.append(f"{out.name}: {e}")
            print(f"  FAILED {out.name}: {e}", file=sys.stderr)

    if episodes:
        assemble_full_episodes(episodes, api_key)
    print(f"done: {synthesized} synthesized, {len(failures)} failed")
    print("BACKFILL reminder: street variants to be regenerated with ElevenLabs later.")
    if failures:
        print(f"{len(failures)} FAILURES — rerun to retry (existing files are skipped)")
        sys.exit(1)


if __name__ == "__main__":
    main()
