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
