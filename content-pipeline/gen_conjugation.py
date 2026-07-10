#!/usr/bin/env python3
"""Generate the Learn/Conjugation module (PLAN2 §3.1).

Reads hand-authored data/verbs.json (présent + imparfait stem + participle/aux),
derives the full four-tense tables (passé composé, futur proche) and street
contractions by rule, then calls Claude per verb for an MT-voice explanation and
15–20 drill sentences exercising the forms in context. Also emits the
conditional-politeness mini-module (fixed forms + drills).

Each verb unit becomes a ConceptNode of type `conjugation` (id conj_{infinitive});
drills are sentences with target_concept_id = the verb node.

Output: learn_conjugation.json

Usage:
    python gen_conjugation.py                    # all 20 verbs + politesse module
    python gen_conjugation.py --verb etre        # one verb (accent-insensitive id)
    python gen_conjugation.py --dry-run          # print prompts, no API calls
    python gen_conjugation.py --force            # regenerate existing units
"""

import argparse
import json
import unicodedata

from genlib import (HERE, STREET_REGISTER_BRIEF, call_claude, load_output,
                    load_v1_graph, make_client, save_output, v1_concept_summaries)

VERBS_PATH = HERE / "data" / "verbs.json"
OUT_PATH = HERE / "learn_conjugation.json"

PERSONS = ["je", "tu", "il", "on", "vous", "ils"]
N_DRILLS = 18  # PLAN2 §3.1: 15–20 per verb
TENSES = ["present", "passe_compose", "imparfait", "futur_proche"]

VOWELS = "aàâeéèêëiîïoôuûh"
IMPARFAIT_ENDINGS = {"je": "ais", "tu": "ais", "il": "ait", "on": "ait", "vous": "iez", "ils": "aient"}
ALLER_PRESENT = {"je": "vais", "tu": "vas", "il": "va", "on": "va", "vous": "allez", "ils": "vont"}
ETRE_PRESENT = {"je": "suis", "tu": "es", "il": "est", "on": "est", "vous": "êtes", "ils": "sont"}
AVOIR_PRESENT = {"je": "ai", "tu": "as", "il": "a", "on": "a", "vous": "avez", "ils": "ont"}
# plural agreement for être-aux participles (masculine default; explanation
# covers the feminine -e, which is inaudible anyway)
PLURAL_PERSONS = {"on", "vous", "ils"}


def slug(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()


def join_subject(person, verb_form):
    """Formal join: elision je -> j' before vowel."""
    if person == "je" and verb_form[0] in VOWELS:
        return "j'" + verb_form
    return f"{person} {verb_form}"


def street_join(person, verb_form, je_reduction):
    """Street join: t' before vowels, j' schwa-drop where flagged."""
    if person == "tu" and verb_form[0] in VOWELS:
        return "t'" + verb_form
    if person == "je" and verb_form[0] not in VOWELS and je_reduction:
        return "j'" + verb_form
    return join_subject(person, verb_form)


def cell(person, verb_form, je_reduction):
    formal = join_subject(person, verb_form)
    street = street_join(person, verb_form, je_reduction)
    c = {"formal": formal}
    if street != formal:
        c["street"] = street
    return c


def compound_cell(person, aux_forms, rest, aux_je_reduction):
    """passé composé / futur proche: contraction applies to the auxiliary."""
    aux = aux_forms[person]
    formal = f"{join_subject(person, aux)} {rest}"
    street = f"{street_join(person, aux, aux_je_reduction)} {rest}"
    c = {"formal": formal}
    if street != formal:
        c["street"] = street
    return c


def build_table(verb):
    red = verb["je_reduction"]
    table = {"present": {}, "passe_compose": {}, "imparfait": {}, "futur_proche": {}}
    for p in PERSONS:
        table["present"][p] = cell(p, verb["present"][p], red)
        table["imparfait"][p] = cell(p, verb["imparfait_stem"] + IMPARFAIT_ENDINGS[p], red)
        if verb["aux"] == "être":
            participle = verb["participle"] + ("s" if p in PLURAL_PERSONS else "")
            # être as aux: j'suis reduction rides on the être flag, not this verb's
            table["passe_compose"][p] = compound_cell(p, ETRE_PRESENT, participle, True)
        else:
            table["passe_compose"][p] = compound_cell(p, AVOIR_PRESENT, verb["participle"], False)
        table["futur_proche"][p] = compound_cell(p, ALLER_PRESENT, verb["infinitive"], True)
    return table


def table_text(table):
    lines = []
    for tense in TENSES:
        forms = ", ".join(
            table[tense][p]["formal"]
            + (f" (street: {table[tense][p]['street']})" if "street" in table[tense][p] else "")
            for p in PERSONS
        )
        lines.append(f"  {tense}: {forms}")
    return "\n".join(lines)


def build_prompt(verb, table, graph):
    return f"""You are writing a unit for "Chais Pas", a Michel Thomas-style spoken-French course with a first-class street-register layer. The learner already knows the v1 curriculum below and is now drilling full conjugation paradigms — this unit covers **{verb['infinitive']}** ({verb['english']}), family: {verb['family']}.

THE VERB'S FORMS (already derived — use them exactly as given):
{table_text(table)}
Street notes: {verb['street_notes']}

V1 CURRICULUM (grammar and register the learner already has — prefer staying inside it):
{v1_concept_summaries(graph)}

{STREET_REGISTER_BRIEF}

TASK — return a JSON object with two keys:

1. "explanation": an MT-style spoken framing of this verb, in English, <= 15 seconds when read aloud (roughly 40-60 words). Conversational, confidence-building, highlights the pattern that makes this verb easy (sound-alike forms, cognate hooks, the street contraction). Never a grammar lecture.

2. "drills": exactly {N_DRILLS} drill sentences exercising the forms in context. Requirements:
   - every sentence uses {verb['infinitive']} as its main event, in one of the four tenses above
   - spread across tenses (roughly 6 present / 4 passé composé / 4 imparfait / 4 futur proche)
   - persons weighted toward spoken priority: mostly je/tu/on/il; ils/elles in only 2-3 drills total; vous in 1-2 drills (the full paradigm lives in the table — drills train what gets said)
   - everyday-France content: café, métro, friends, plans, work, weather — short and sayable (3-10 words of French)
   - vocabulary: prefer words from the v1 curriculum examples above plus obvious cognates; no rare vocabulary
   - each drill: {{"english": "...", "french_formal": "...", "french_street": "...", "tense": "present|passe_compose|imparfait|futur_proche", "concept_ids": [v1 concept ids actually used, e.g. "negation_pas" if the sentence is negated]}}
   - french_street applies the street rules above (ne-drop, t'as, {'' if not verb['je_reduction'] else "j'" + verb['present']['je'] + ', '}y'a...)
   - vary length, no duplicates, no near-duplicates

Output ONLY the JSON object, no prose, no code fences."""


POLITESSE_PROMPT = """You are writing the conditional-politeness mini-unit for "Chais Pas", a Michel Thomas-style spoken-French course. The learner knows the v1 curriculum below, including the conditional_softeners node (je voudrais, ça serait). This unit deepens it into the fixed politeness toolkit for everyday-France transactions.

THE FORMS (use them exactly as given):
{forms}

V1 CURRICULUM:
{summaries}

{street_brief}

TASK — return a JSON object with two keys:

1. "explanation": MT-style spoken framing in English, <= 15 seconds aloud (40-60 words): these are the magic politeness words that make every shop, café and hotel interaction smooth — one fixed form each, no conjugation to learn.

2. "drills": exactly 16 drill sentences. Requirements:
   - every sentence is built on one of the forms above
   - transactional everyday-France content: ordering, asking for things, suggesting plans, softening requests
   - each drill: {{"english": "...", "french_formal": "...", "french_street": "...", "form": "je voudrais|j'aimerais|je pourrais|tu pourrais|vous pourriez|il faudrait|ce serait", "concept_ids": [v1 concept ids actually used]}}
   - street register per the rules above (il faudrait -> faudrait, ce serait -> ça serait)
   - vary length 3-10 French words, no duplicates

Output ONLY the JSON object, no prose, no code fences."""


def node_for_verb(verb, table, gen):
    drills = []
    nid = f"conj_{slug(verb['infinitive'])}"
    for i, d in enumerate(gen["drills"], 1):
        drills.append({
            "id": f"{nid}_{i:03d}",
            "target_concept_id": nid,
            "concept_ids": sorted(set(d.get("concept_ids", [])) | {nid}),
            "english": d["english"].strip(),
            "french_formal": d["french_formal"].strip(),
            "french_street": d["french_street"].strip(),
            "tense": d.get("tense", ""),
        })
    return {
        "id": nid,
        "type": "conjugation",
        "tier": verb["tier"],
        "prereq_ids": [],
        "family": verb["family"],
        "infinitive": verb["infinitive"],
        "title": f"{verb['infinitive']} — {verb['english']}",
        "english": verb["english"],
        "explanation": gen["explanation"].strip(),
        "street_notes": verb["street_notes"],
        "aux": verb["aux"],
        "participle": verb["participle"],
        "table": table,
        "drills": drills,
    }


def node_for_politesse(spec, gen):
    nid = spec["id"]
    drills = []
    for i, d in enumerate(gen["drills"], 1):
        drills.append({
            "id": f"{nid}_{i:03d}",
            "target_concept_id": nid,
            "concept_ids": sorted(set(d.get("concept_ids", [])) | {nid}),
            "english": d["english"].strip(),
            "french_formal": d["french_formal"].strip(),
            "french_street": d["french_street"].strip(),
            "form": d.get("form", ""),
        })
    return {
        "id": nid,
        "type": "conjugation",
        "tier": spec["tier"],
        "prereq_ids": spec["prereq_ids"],
        "family": "politesse",
        "title": spec["title"],
        "explanation": gen["explanation"].strip(),
        "forms": spec["forms"],
        "drills": drills,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verb", action="append",
                    help="only these verbs (accent-insensitive: etre, aller, 'politesse')")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(VERBS_PATH) as f:
        data = json.load(f)
    graph = load_v1_graph()
    out = load_output(OUT_PATH, "nodes")
    done = {n["id"] for n in out["nodes"]}

    wanted = {slug(v).lower() for v in args.verb} if args.verb else None
    client = None if args.dry_run else make_client()

    units = [("verb", v) for v in sorted(data["verbs"], key=lambda v: v["rank"])]
    units.append(("politesse", data["politesse"]))

    for kind, spec in units:
        if kind == "verb":
            nid, label = f"conj_{slug(spec['infinitive'])}", spec["infinitive"]
            if wanted and slug(spec["infinitive"]).lower() not in wanted:
                continue
        else:
            nid, label = spec["id"], "politesse"
            if wanted and "politesse" not in wanted:
                continue
        if nid in done and not args.force:
            print(f"[skip] {nid} (exists; --force to redo)")
            continue

        if kind == "verb":
            table = build_table(spec)
            prompt = build_prompt(spec, table, graph)
        else:
            forms = "\n".join(f"  {f['formal']}" +
                              (f" (street: {f['street']})" if f["street"] != f["formal"] else "") +
                              f" — {f['english']}" for f in spec["forms"])
            prompt = POLITESSE_PROMPT.format(forms=forms,
                                             summaries=v1_concept_summaries(graph),
                                             street_brief=STREET_REGISTER_BRIEF)

        print(f"[gen ] {nid}")
        if args.dry_run:
            print(prompt + "\n" + "=" * 80)
            continue

        gen = call_claude(client, prompt, label=label)
        if not isinstance(gen, dict) or "explanation" not in gen or not gen.get("drills"):
            raise RuntimeError(f"{nid}: malformed generation result")
        node = node_for_verb(spec, table, gen) if kind == "verb" else node_for_politesse(spec, gen)
        out["nodes"] = [n for n in out["nodes"] if n["id"] != nid] + [node]
        save_output(OUT_PATH, out)
        print(f"       {len(node['drills'])} drills written")

    print(f"\nTotal conjugation nodes in {OUT_PATH.name}: {len(out['nodes'])}")


if __name__ == "__main__":
    main()
