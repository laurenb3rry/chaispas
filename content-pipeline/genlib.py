#!/usr/bin/env python3
"""Shared helpers for the v2 content generators (PLAN2 §3.7).

Claude client setup, JSON response parsing with retries, and v1 graph access —
the pieces gen_conjugation.py / gen_vocab.py / gen_grammar.py have in common.
"""

import json
import re
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

HERE = Path(__file__).parent
MODEL = "claude-sonnet-4-6"
MAX_TOKENS = 16000


def make_client():
    load_dotenv(HERE / ".env")
    import anthropic

    return anthropic.Anthropic()  # reads ANTHROPIC_API_KEY


def parse_json_response(text):
    """Extract the first JSON object or array from a model response."""
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    starts = [i for i in (text.find("{"), text.find("[")) if i != -1]
    if not starts:
        raise ValueError("no JSON in response")
    start = min(starts)
    end = (text.rfind("}") if text[start] == "{" else text.rfind("]")) + 1
    return json.loads(text[start:end])


def call_claude(client, prompt, max_tokens=MAX_TOKENS, retries=3, label=""):
    """Call the model, parse JSON, retry on failure."""
    for attempt in range(retries):
        try:
            resp = client.messages.create(
                model=MODEL,
                max_tokens=max_tokens,
                messages=[{"role": "user", "content": prompt}],
            )
            return parse_json_response(resp.content[0].text)
        except Exception as e:
            print(f"    attempt {attempt + 1} failed{f' ({label})' if label else ''}: {e}",
                  file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"generation failed after {retries} attempts{f' ({label})' if label else ''}")


def load_v1_graph():
    with open(HERE / "graph.json") as f:
        return json.load(f)


def v1_concept_summaries(graph, max_examples=3):
    """One line per v1 concept — grammar/register context for v2 prompts."""
    lines = []
    for node in graph["nodes"]:
        ex = "; ".join(
            f"\"{e['formal']}\" / street: \"{e['street']}\" ({e['english']})"
            for e in node["canonical_examples"][:max_examples]
        )
        lines.append(f"- {node['id']} ({node['type']}): {node['title']}. Examples: {ex}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Phase 10b: voice spec + structured explanation schema, shared by
# gen_conjugation.py and gen_grammar.py. The few-shot exemplars live in
# data/explanation_exemplars.json (user-approved 2026-07-15); nodes present
# there ship the exemplar explanation verbatim instead of a generated one.

VOICE_SPEC = """VOICE (applies to every explanation):
Write like an expert teacher writing a reference their students actually read: direct, warm, plain.
- Explain WHY a rule exists or why French does it this way whenever there is a real reason — a learner who knows the why stops memorizing.
- Every sentence must teach something. If a sentence only encourages, delete it.
- Plain register: no hype metaphors (banned outright: weaponize, unfair advantage, VIP, superpower, game-changer, magic, secret weapon, hack, cheat code), no cheerleading ("You've got this!", "amazing"), no marketing rhythm.
- Address the learner as "you". Contractions are fine. Short sentences are fine.
- Concrete over abstract: show the form in a real sentence rather than describing it.
- It is fine to say something is hard or irregular — say it once, then show the pattern that tames it."""

EXPLANATION_SCHEMA = """"explanation" is an ORDERED ARRAY of sections. Each section:
  {"header": "2-6 plain words", "body": "1-3 sentences", "bullets": ["optional — only for genuinely enumerable facts"], "examples": [{"french": "...", "english": "..."}]}
"bullets" and "examples" are optional per section; use them where they clarify, never as decoration."""


def load_exemplars():
    with open(HERE / "data" / "explanation_exemplars.json") as f:
        return json.load(f)


def exemplar_block(kind):
    """Few-shot block for the generation prompts. kind: 'verb' | 'grammar'."""
    ex = load_exemplars()
    if kind == "verb":
        pairs = [("être — to be", ex["verb_exemplars"]["conj_etre"]),
                 ("attendre — to wait (for)", ex["verb_exemplars"]["conj_attendre"])]
    else:
        pairs = [("Gender & articles", ex["grammar_exemplars"]["gram_gender_articles"]),
                 ("Survival subjunctive", ex["grammar_exemplars"]["gram_subjonctif_survival"])]
    body = "\n".join(
        f"--- exemplar: {title} ---\n{json.dumps(sections, ensure_ascii=False, indent=1)}"
        for title, sections in pairs
    )
    return ("EXEMPLARS — match this register, density and structure exactly; "
            "never copy their content:\n" + body)


def exemplar_explanation(node_id):
    """The approved hand-written explanation for this node, if one exists."""
    ex = load_exemplars()
    return ex["verb_exemplars"].get(node_id) or ex["grammar_exemplars"].get(node_id)


STREET_REGISTER_BRIEF = """Street register rules (apply to every french_street field):
- ne-drop is the norm: "c'est pas grave", "j'ai rien dit"
- tu + vowel contracts: t'as, t'es, t'étais
- je + consonant reduces in fast speech where natural: j'veux, j'sais (chais), j'peux, j'suis
- il y a → y'a; on replaces nous everywhere
- If nothing applies, french_street may equal french_formal — never invent slang vocabulary just to differ."""


def load_output(path, key):
    """Load an existing generator output file, or an empty skeleton."""
    if Path(path).exists():
        with open(path) as f:
            return json.load(f)
    return {"version": 2, key: []}


def save_output(path, data):
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
