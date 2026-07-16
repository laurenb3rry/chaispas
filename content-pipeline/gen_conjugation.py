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

from genlib import (EXPLANATION_SCHEMA, HERE, STREET_REGISTER_BRIEF, VOICE_SPEC,
                    call_claude, exemplar_block, exemplar_explanation,
                    flatten_sections, load_output, load_prior_explanations,
                    load_v1_graph, make_client, save_output, v1_concept_summaries)

VERBS_PATH = HERE / "data" / "verbs.json"
TENSE_USAGE_PATH = HERE / "data" / "tense_usage.json"
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


def imparfait_form(stem, ending):
    """-ger/-cer softening: the e/ç exist only to keep the stem's sound
    before a; before i they must go (mangeais but mangiez, commençais but
    commenciez). This fixes the 'vous mangeiez' bug shipped in v2a."""
    if ending.startswith("i"):
        if stem.endswith("ge"):
            return stem[:-1] + ending
        if stem.endswith("ç"):
            return stem[:-1] + "c" + ending
    return stem + ending


def build_table(verb):
    red = verb["je_reduction"]
    table = {"present": {}, "passe_compose": {}, "imparfait": {}, "futur_proche": {}}
    for p in PERSONS:
        table["present"][p] = cell(p, verb["present"][p], red)
        table["imparfait"][p] = cell(p, imparfait_form(verb["imparfait_stem"], IMPARFAIT_ENDINGS[p]), red)
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

{VOICE_SPEC}

TASK — return a JSON object with two keys:

1. {EXPLANATION_SCHEMA}
   - 2-4 sections; total word count across headers, bodies and bullets <= 160 — treat 160 as a hard ceiling. Density beats length.
   - Teach usage: when this verb gets chosen, the mistakes an English speaker makes with it, what actually gets said in real speech. Never etymology for its own sake.

{exemplar_block('verb')}

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

{voice}

TASK — return a JSON object with two keys:

1. {schema}
   - 2-4 sections; total word count across headers, bodies and bullets <= 160 — treat 160 as a hard ceiling. Density beats length.
   - The teaching point: these are fixed forms — no conjugation — and why the conditional softens a request (it frames it as hypothetical, so nobody is being ordered around).

{exemplars}

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
        # approved exemplar explanations (être, attendre) ship verbatim
        "explanation": exemplar_explanation(nid) or gen["explanation"],
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
        "explanation": exemplar_explanation(nid) or gen["explanation"],
        "forms": spec["forms"],
        "drills": drills,
    }


# --- phase 10b: explanation-only regeneration for units that already have
# drills (drills, and therefore audio, must not change) -----------------------

EXPLANATION_ONLY_PROMPT = """{voice}

You are rewriting the learner-facing explanation for one unit of "Chais Pas", a spoken-French course with a first-class street-register layer. The unit's conjugation table and drills already exist — write ONLY the explanation that sits above the table.

UNIT: {label}
FORMS:
{forms}
Street notes: {street_notes}

SOURCE MATERIAL — the previous explanation. It carries the essential teaching points: keep every fact, compress and re-chunk the delivery into the register below. Do not copy its sentences; do not drop a teaching point.
{prior}

{schema}
- 2-4 sections; total word count across headers, bodies and bullets <= 160 — treat 160 as a hard ceiling. Density beats length.
- Teach usage: when this verb gets chosen, the mistakes an English speaker makes with it, what actually gets said in real speech. Never etymology for its own sake.

{exemplars}

Return ONLY a JSON object: {{"explanation": [ ...sections... ]}}"""


def regen_explanation(client, label, forms_text, street_notes, prior):
    prompt = EXPLANATION_ONLY_PROMPT.format(
        voice=VOICE_SPEC, label=label, forms=forms_text,
        street_notes=street_notes, schema=EXPLANATION_SCHEMA,
        prior=prior or "(none available — teach from the forms and street notes)",
        exemplars=exemplar_block("verb"))
    gen = call_claude(client, prompt, label=label)
    if not isinstance(gen, dict) or not isinstance(gen.get("explanation"), list):
        raise RuntimeError(f"{label}: explanation regen returned wrong shape")
    return gen["explanation"]


def refresh_existing_node(node, specs_by_id, client, dry_run, priors):
    """Rebuild spec-derived fields (incl. the corrected imparfait table) and
    replace the explanation; drills are never touched."""
    nid = node["id"]
    if node.get("family") == "politesse":
        forms_text = "\n".join(
            f"  {f['formal']}"
            + (f" (street: {f['street']})" if f["street"] != f["formal"] else "")
            + f" — {f['english']}" for f in node["forms"])
        street_notes = "il faudrait -> faudrait, ce serait -> ça serait"
        label = "politesse"
    else:
        spec = specs_by_id[nid]
        table = build_table(spec)
        node["table"] = table
        node["street_notes"] = spec["street_notes"]
        node["tier"] = spec["tier"]
        node["family"] = spec["family"]
        forms_text = table_text(table)
        street_notes = spec["street_notes"]
        label = spec["infinitive"]

    if dry_run:
        print(f"[dry ] would regenerate explanation for {nid}")
        return
    node["explanation"] = exemplar_explanation(nid) \
        or regen_explanation(client, label, forms_text, street_notes,
                             flatten_sections(priors.get(nid)))


def load_tense_usage():
    with open(TENSE_USAGE_PATH) as f:
        return json.load(f)["tenses"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verb", action="append",
                    help="only these verbs (accent-insensitive: etre, aller, 'politesse')")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--explanations-only", action="store_true",
                    help="phase 10b: regenerate explanations (and rebuild tables) "
                         "for EXISTING units without touching their drills")
    args = ap.parse_args()

    with open(VERBS_PATH) as f:
        data = json.load(f)
    graph = load_v1_graph()
    out = load_output(OUT_PATH, "nodes")
    out["tense_usage"] = load_tense_usage()
    done = {n["id"] for n in out["nodes"]}

    wanted = {slug(v).lower() for v in args.verb} if args.verb else None
    client = None if args.dry_run else make_client()

    if args.explanations_only:
        specs_by_id = {f"conj_{slug(v['infinitive'])}": v for v in data["verbs"]}
        priors = load_prior_explanations("conjugation")
        for node in out["nodes"]:
            label = node.get("infinitive", "politesse")
            if wanted and slug(label).lower() not in wanted:
                continue
            # resumable: structured explanations are lists, legacy are strings
            if isinstance(node.get("explanation"), list) and not args.force:
                print(f"[skip] {node['id']} (already structured; --force to redo)")
                continue
            print(f"[expl] {node['id']}")
            refresh_existing_node(node, specs_by_id, client, args.dry_run, priors)
            if not args.dry_run:
                save_output(OUT_PATH, out)
        print(f"\nexplanations refreshed; {len(out['nodes'])} nodes in {OUT_PATH.name}")
        return

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
                                             street_brief=STREET_REGISTER_BRIEF,
                                             voice=VOICE_SPEC,
                                             schema=EXPLANATION_SCHEMA,
                                             exemplars=exemplar_block("verb"))

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
