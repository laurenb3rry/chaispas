#!/usr/bin/env python3
"""Constraint checker for generated drill sentences (PLAN.md section 5).

Verifies, for each sentence in sentences.json:
  1. its claimed concept_ids are a subset of {target concept + transitive prereqs}
  2. no detectable construction appears whose concept is outside the allowed set
     (pattern detectors — a filter, not a proof)
  3. every French token is in the allowed lexicon (function words + words from
     allowed concepts' canonical examples + cognates when cognate_bridges is allowed)

Also validates graph.json itself (DAG consistency).

Writes sentences_validated.json (passing sentences) and validation_report.json.
Usage: python validate.py [--strict]  (--strict: exit 1 if anything rejected)
"""

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).parent

# Closed-class words allowed everywhere (articles, prepositions, pronouns,
# apostrophe fragments, numbers, high-frequency adverbs used in examples).
FUNCTION_WORDS = {
    "je", "j", "tu", "t", "il", "elle", "on", "nous", "vous", "ils", "elles",
    "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "au", "aux",
    "à", "en", "et", "ou", "mais", "que", "qu", "qui", "quoi", "où", "quand",
    "combien", "pourquoi", "comment", "ce", "c", "ça", "cela", "ne", "n",
    "pas", "plus", "très", "bien", "ici", "là", "oui", "non", "ouais", "si",
    "me", "m", "te", "se", "s", "lui", "leur", "y", "moi", "toi",
    "est", "es", "suis", "sont", "sommes", "êtes", "être", "avec", "pour",
    "dans", "sur", "aussi", "encore", "toujours", "aujourd", "hui", "demain",
    "maintenant", "ans", "heures", "heure",
    "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix",
    "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "votre",
    "cette", "cet", "ces", "an", "bas", "quelque", "chose",
    # proper names used in prompts/examples
    "lauren", "laurent", "paris", "france", "marie", "pierre", "lyon",
}

# Extra vocabulary per concept, beyond what its canonical examples contain.
# Extend freely as generation reveals legitimate-but-missing words.
CONCEPT_EXTRA_VOCAB = {
    "cognate_bridges": {"question", "attention", "impossible", "probable",
                        "adorable", "capable", "horrible", "extraordinaire",
                        "nation", "invitation", "réservation", "table"},
    "je_veux": {"veux", "café", "taxi", "parler", "parle", "parles", "manger",
                "voir", "travailler", "comprendre", "français"},
    "vouloir_present": {"vouloir"},
    "aller_places": {"aller"},
    "y_en": {"aller"},
    "pc_avoir": {"mangé", "vu", "fait", "dit", "fini", "compris", "parlé",
                 "pris", "eu", "été", "voulu", "pu", "ai", "as", "a", "avons",
                 "avez", "ont"},
    "pc_etre": {"allé", "allée", "allés", "parti", "partie", "partis",
                "arrivé", "arrivée", "arrivés", "venu", "venue", "venus",
                "resté", "restée", "restés", "sorti", "sortie", "sortis",
                "rentré", "rentrée", "rentrés",
                "arriver", "arrive", "sortir", "rester", "rentrer"},
    "faire_expressions": {"fais", "fait", "faites", "beau", "froid", "chaud",
                          "rire", "longtemps"},
    "imparfait_vs_pc": {"étais", "était", "étions", "étiez", "étaient",
                        "faisais", "faisait", "voulais", "voulait",
                        "avais", "avait", "allais", "allait",
                        "pouvais", "pouvait", "devais", "devait",
                        "mangeais", "mangeait", "parlais", "parlait",
                        "fatigué", "fatiguée", "facile", "super"},
    "conditional_softeners": {"voudrais", "voudrait", "voudrions", "voudriez",
                              "serais", "serait", "pourrais", "pourrait",
                              "pourrions", "pourriez", "devrais", "devrait",
                              "devrions", "aimerais", "aimerait"},
    "reflexives": {"lever", "lève", "lèves", "levez",
                   "préparer", "prépare", "prépares", "préparez",
                   "reposer", "repose", "reposes", "reposez",
                   "demander", "demande", "demandes", "demandez",
                   "coucher", "couche", "couches", "couchez",
                   "réveiller", "réveille", "réveilles",
                   "souvenir", "souviens", "souvient", "souvenez",
                   "appeler", "appelle", "appelles", "appelez"},
}

# Construction detectors: regex on french text -> required concept id.
# Applied to both formal and street variants (lowercased, NFC).
SUBJ = r"(?:je |j'|tu |t'|il |elle |on |nous |vous |qui )"
DETECTORS = [
    # passé composé with avoir
    (re.compile(SUBJ + r"?(?:ai|as|a|avons|avez|ont) (?:pas )?(?:\w+é|vu|fait|dit|fini|compris|pris|mis|eu|été|voulu|pu|dû)\b"), "pc_avoir"),
    # passé composé with être (movement verbs)
    (re.compile(r"(?:suis|es|est|sommes|êtes|sont) (?:pas )?(?:allé|parti|arrivé|venu|resté|sorti|entré|rentré|monté|descendu|tombé|né|mort)\w*\b"), "pc_etre"),
    # futur proche: aller + infinitive
    (re.compile(r"\b(?:vais|vas|va|allons|allez) (?:pas )?\w+(?:er|ir|re|oir)\b"), "futur_proche"),
    # aller + place
    (re.compile(r"\b(?:vais|vas|va|allons|allez) (?:pas )?(?:à|au|aux|en) \w+"), "aller_places"),
    # conditional softeners
    (re.compile(r"\b(?:voudrais|voudrait|serait|s'rait|pourrais|pourrait|pourriez|devrais|devrait|devrions|aimerais|aimerait)\b"), "conditional_softeners"),
    # direct object pronoun before verb
    (re.compile(r"(?:je |j'|tu |on |nous |vous |peux |peut |pouvez |veux |veut |voulons |dois |doit |vais |va )(?:le |la |les |l')\w+"), "dobj_pronouns"),
    # indirect object pronoun before verb ('fais' excluded: 'tu me fais rire'
    # belongs to faire_expressions; conjugated 'appelle' excluded: 'je
    # m'appelle' is reflexive — only infinitive 'appeler' signals iobj here)
    (re.compile(r"\b(?:me|m'|te|t'|lui|leur)\s?(?:parle|parler|dire|dis|dit|aider|aide|appeler|jure|montrer|montre|donner|donne)\w*\b"), "iobj_pronouns"),
    # y / en pronouns
    (re.compile(r"\b(?:j'y|t'y|on y|il y en|y'en|j'en|t'en|il en|elle en|on en|vous en)\b"), "y_en"),
    # il y a / y'a existential, chais pas reduction
    # (t'as/t'es are NOT flagged here: they ride along with whatever
    # construction they belong to, per that node's own street_mapping)
    (re.compile(r"\b(?:il (?:n')?y a|y'a|chais pas|chuis)\b"), "connected_speech"),
    # reflexive verbs (curated stems to avoid clashing with iobj me/te)
    (re.compile(r"\b(?:me|m'|te|t'|se|s')\s?(?:lève|appelle|appelles|souviens|souvient|demande|repose|prépare|couche|réveille|voit|voient|sens)\b"), "reflexives"),
    # imparfait (curated forms; generic -ais/-ait matching hits 'français'/'fait')
    (re.compile(r"\b(?:étais|était|étions|étiez|étaient|faisais|faisait|voulais|voulait|allais|allait|avais|avait|mangeais|mangeait|parlais|parlait|pouvais|pouvait|devais|devait)\b"), "imparfait_vs_pc"),
    # pouvoir / devoir
    (re.compile(r"\b(?:peux|peut|pouvons|pouvez)\b"), "pouvoir_inf"),
    (re.compile(r"\b(?:dois|doit|devons|devez)\b"), "devoir_inf"),
    # negation
    (re.compile(r"\bpas\b"), "negation_pas"),
    # on as subject (taught in vouloir_present's conjugation set)
    (re.compile(r"\bon \w+"), "vouloir_present"),
]

# vouloir needs special-casing: "je veux" alone is je_veux; other persons are vouloir_present.
VOULOIR_NON_JE = re.compile(r"\b(?:tu veux|il veut|elle veut|on veut|vous voulez|nous voulons|veut|voulez|voulons)\b")
QUESTION_MARK = re.compile(r"\?")
# relatives checked separately: 'est-ce que' must be stripped first or every
# formal question would false-positive as a relative clause
EST_CE_QUE = re.compile(r"qu'est-ce qu(?:e|')|est-ce qu(?:e|')")
RELATIVE = re.compile(r"\w+ (?:qui|que|qu')\s?\w+")


def norm(s):
    return unicodedata.normalize("NFC", s.lower())


def tokenize(s):
    s = norm(s)
    s = re.sub(r"[.,!?;:…«»\"()—–-]", " ", s)
    s = s.replace("’", "'")
    return [t for part in s.split() for t in part.split("'") if t]


COGNATE = re.compile(r"^[a-zà-ÿ]+(?:tion|sion|able|ible|aire|ique)s?$")


def in_lexicon(token, lex):
    """Direct hit, or inflected form of a known word (plural -s, feminine -e)."""
    if token in lex:
        return True
    for stripped in (token.rstrip("s"), token.rstrip("s").rstrip("e")):
        if stripped and stripped in lex:
            return True
    return False


def ancestors(nid, nodes_by_id, acc=None):
    if acc is None:
        acc = set()
    for pid in nodes_by_id[nid]["prereq_ids"]:
        if pid not in acc:
            acc.add(pid)
            ancestors(pid, nodes_by_id, acc)
    return acc


def validate_graph(graph):
    """DAG consistency: unique ids, prereqs exist, acyclic, tier ordering."""
    errors = []
    nodes = graph["nodes"]
    ids = [n["id"] for n in nodes]
    if len(ids) != len(set(ids)):
        errors.append("duplicate node ids")
    nodes_by_id = {n["id"]: n for n in nodes}
    for n in nodes:
        for p in n["prereq_ids"]:
            if p not in nodes_by_id:
                errors.append(f"{n['id']}: unknown prereq {p}")
            elif nodes_by_id[p]["tier"] > n["tier"]:
                errors.append(f"{n['id']}: prereq {p} has higher tier")
    seen, stack = set(), []

    def visit(nid):
        if nid in stack:
            errors.append(f"cycle: {' -> '.join(stack + [nid])}")
            return
        if nid in seen:
            return
        seen.add(nid)
        stack.append(nid)
        for p in nodes_by_id.get(nid, {}).get("prereq_ids", []):
            visit(p)
        stack.pop()

    for nid in nodes_by_id:
        visit(nid)
    return errors


def build_lexicon(allowed_ids, nodes_by_id):
    lex = set(FUNCTION_WORDS)
    for aid in allowed_ids:
        for ex in nodes_by_id[aid]["canonical_examples"]:
            lex.update(tokenize(ex["formal"]))
            lex.update(tokenize(ex["street"]))
        lex.update(CONCEPT_EXTRA_VOCAB.get(aid, set()))
    return lex


def check_sentence(s, nodes_by_id):
    violations = []
    target = s["target_concept_id"]
    if target not in nodes_by_id:
        return [f"unknown target concept {target}"]
    allowed = ancestors(target, nodes_by_id) | {target}

    claimed = set(s["concept_ids"])
    if not claimed <= allowed:
        violations.append(f"claimed concepts outside allowed set: {sorted(claimed - allowed)}")
    if target not in claimed:
        violations.append("target concept missing from concept_ids")

    text = norm(s["french_formal"]) + " || " + norm(s["french_street"])

    for pattern, concept in DETECTORS:
        if concept is None:
            continue
        if pattern.search(text) and concept not in allowed:
            violations.append(f"detected '{concept}' construction not in allowed set (pattern: {pattern.pattern[:60]})")

    if VOULOIR_NON_JE.search(text) and "vouloir_present" not in allowed:
        violations.append("non-je vouloir form but vouloir_present not allowed")

    if RELATIVE.search(EST_CE_QUE.sub(" ", text)) and "relatives_qui_que" not in allowed:
        violations.append("relative clause (qui/que) but relatives_qui_que not allowed")

    if QUESTION_MARK.search(text) and "questions_intonation" not in allowed \
            and nodes_by_id[target]["type"] != "chunk":
        violations.append("question form but questions_intonation not allowed")

    lex = build_lexicon(allowed, nodes_by_id)
    cognates_ok = "cognate_bridges" in allowed
    for token in tokenize(s["french_formal"]) + tokenize(s["french_street"]):
        if in_lexicon(token, lex):
            continue
        if cognates_ok and COGNATE.match(token):
            continue
        violations.append(f"unknown vocab: '{token}'")

    return violations


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="exit 1 on any rejection")
    ap.add_argument("--sentences", default=HERE / "sentences.json", type=Path)
    args = ap.parse_args()

    with open(HERE / "graph.json") as f:
        graph = json.load(f)
    graph_errors = validate_graph(graph)
    if graph_errors:
        print("GRAPH ERRORS:")
        for e in graph_errors:
            print(f"  - {e}")
        sys.exit(1)
    print(f"graph.json OK ({len(graph['nodes'])} nodes, DAG consistent)")

    if not args.sentences.exists():
        print(f"{args.sentences.name} not found — graph-only validation done.")
        return

    with open(args.sentences) as f:
        data = json.load(f)
    nodes_by_id = {n["id"]: n for n in graph["nodes"]}

    passed, rejected = [], []
    for s in data["sentences"]:
        violations = check_sentence(s, nodes_by_id)
        if violations:
            rejected.append({"id": s["id"], "french_formal": s["french_formal"],
                             "violations": violations})
        else:
            passed.append(s)

    with open(HERE / "sentences_validated.json", "w") as f:
        json.dump({"version": data.get("version", 1), "sentences": passed},
                  f, ensure_ascii=False, indent=2)
    with open(HERE / "validation_report.json", "w") as f:
        json.dump({"passed": len(passed), "rejected": len(rejected),
                   "rejections": rejected}, f, ensure_ascii=False, indent=2)

    print(f"sentences: {len(passed)} passed, {len(rejected)} rejected")
    if rejected:
        print("sample rejections:")
        for r in rejected[:10]:
            print(f"  {r['id']}: {r['violations'][0]}")
        print("full detail in validation_report.json")
    if rejected and args.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()
