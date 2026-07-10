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


def deaccent(s):
    """Accent/ligature-insensitive comparison key (préfère->prefere, œil->oeil)."""
    s = s.replace("œ", "oe").replace("æ", "ae")
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()


# Stems (deaccented) for verbs whose conjugated forms escape the regular
# lemma[:-2] prefix rule. A filter, not a proof — mild false positives are fine.
IRREGULAR_STEMS = {
    "mourir": ("meur", "mort"), "valoir": ("vau", "val"),
    "recevoir": ("recoi", "recev", "recu"), "asseoir": ("assied", "assey", "assis"),
    "prévoir": ("prevu", "prevoi"), "boire": ("boi", "buv"),
    "promettre": ("promet", "promis"), "apprendre": ("apprend", "appris"),
    "vivre": ("viv", "vecu"), "suivre": ("suiv", "suivi"),
    "craindre": ("crain", "craint"), "ouvrir": ("ouvr", "ouvert"),
    "offrir": ("offr", "offert"), "découvrir": ("decouvr", "decouvert"),
    "tenir": ("tien", "tenu"), "revenir": ("revien", "revenu"),
    "devenir": ("devien", "devenu"), "obtenir": ("obtien", "obtenu"),
    "appartenir": ("appartien", "apparten"),
    "sentir": ("sen", "senti"), "ressentir": ("ressen",), "sortir": ("sor",),
    "dormir": ("dor",), "servir": ("ser", "servi"), "mentir": ("men", "menti"),
    "tuer": ("tue",), "plaire": ("plai",),
    "connaître": ("connai",), "paraître": ("parai",),
    # irregular feminines beyond the doubled-consonant rule
    "blanc": ("blanch",), "frais": ("fraich",), "fou": ("foll",),
}


def lemma_in_text(lemma, text_tokens):
    """Loose lemma match for vocab coverage: exact token, plural/feminine strip,
    or verb-stem prefix — all accent-insensitive. Shared with gen_vocab.py."""
    if "'" in lemma or "-" in lemma:
        # multiword lemmas (d'accord, peut-être) tokenize into pieces
        return all(p in text_tokens for p in tokenize(lemma))
    toks = {deaccent(t) for t in text_tokens}
    lem = deaccent(lemma)
    if lem in toks:
        return True
    for t in toks:
        t2 = t.rstrip("s").rstrip("e")
        if t.rstrip("s") == lem or t2 == lem.rstrip("e"):
            return True
        if len(t2) >= 2 and t2[-1] == t2[-2] and t2[:-1] == lem:
            return True  # patronne -> patron, gentille -> gentil
        if lem.endswith("eux") and t2.endswith("eus") and t2[:-3] == lem[:-3]:
            return True  # amoureuse -> amoureux
        # same word family (journée/jour, travailler/travail) — coverage filter,
        # not a proof; short lemmas guarded against runaway prefixing
        if len(lem) >= 4 and t.startswith(lem):
            return True
        if len(t) >= 5 and lem.startswith(t):
            return True
    stems = set(IRREGULAR_STEMS.get(lemma, ()))
    if lem[-2:] in ("er", "ir", "re") and len(lem) > 4:
        stem = lem[:-2]
        stems.add(stem)
        if len(stem) >= 2 and stem[-1] == stem[-2]:
            stems.add(stem[:-1])  # promett -> promet, jett -> jet
    return any(len(s) >= 3 and any(t.startswith(s) for t in toks) for s in stems)


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


# ---------------------------------------------------------------------------
# v2 validation (PLAN2 §3.7): schema checks per Learn content type, DAG checks
# for the new concept nodes against the combined v1+v2 graph, vocab-pack word
# coverage, and warn-level (not reject) vocabulary checks — per plan, v2 Learn
# content is best-effort constrained, so structural problems are errors but
# vocabulary drift is only warned about.

V2_MODULES = ("conjugation", "vocab", "grammar")
V2_TYPES = {"conjugation", "vocab_pack", "grammar"}
V2_TENSES = ("present", "passe_compose", "imparfait", "futur_proche")
V2_PERSONS = ("je", "tu", "il", "on", "vous", "ils")


def load_v2_module(module):
    path = HERE / f"learn_{module}.json"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def validate_v2_dag(v1_nodes, v2_nodes):
    """Combined-graph checks: unique ids, known types, resolvable prereqs, acyclic."""
    errors = []
    all_ids = [n["id"] for n in v1_nodes] + [n["id"] for n in v2_nodes]
    dupes = {i for i in all_ids if all_ids.count(i) > 1}
    if dupes:
        errors.append(f"duplicate node ids across v1+v2: {sorted(dupes)}")
    by_id = {n["id"]: n for n in v1_nodes + v2_nodes}
    for n in v2_nodes:
        if n.get("type") not in V2_TYPES:
            errors.append(f"{n['id']}: unknown v2 type '{n.get('type')}'")
        for p in n.get("prereq_ids", []):
            if p not in by_id:
                errors.append(f"{n['id']}: unknown prereq {p}")

    seen, stack = set(), []

    def visit(nid):
        if nid in stack:
            errors.append(f"cycle: {' -> '.join(stack + [nid])}")
            return
        if nid in seen or nid not in by_id:
            return
        seen.add(nid)
        stack.append(nid)
        for p in by_id[nid].get("prereq_ids", []):
            visit(p)
        stack.pop()

    for nid in by_id:
        visit(nid)
    return errors


def v2_base_lexicon(v1_nodes):
    """Known-word set for warn-level vocab checks: function words + everything
    that appears in v1 canonical examples and validated v1 sentences."""
    lex = set(FUNCTION_WORDS)
    for n in v1_nodes:
        for ex in n["canonical_examples"]:
            lex.update(tokenize(ex["formal"]))
            lex.update(tokenize(ex["street"]))
        lex.update(CONCEPT_EXTRA_VOCAB.get(n["id"], set()))
    v1_sentences = HERE / "sentences_validated.json"
    if v1_sentences.exists():
        with open(v1_sentences) as f:
            for s in json.load(f)["sentences"]:
                lex.update(tokenize(s["french_formal"]))
                lex.update(tokenize(s["french_street"]))
    return lex


def check_drill_fields(drill, node_id):
    problems = []
    for field in ("id", "english", "french_formal", "french_street"):
        if not str(drill.get(field, "")).strip():
            problems.append(f"empty {field}")
    if drill.get("target_concept_id") != node_id:
        problems.append("target_concept_id != node id")
    return problems


def unknown_tokens(drill, lex, extra):
    toks = tokenize(drill["french_formal"]) + tokenize(drill["french_street"])
    return sorted({t for t in toks
                   if not in_lexicon(t, lex) and not in_lexicon(t, extra)
                   and not COGNATE.match(t)})


def verb_form_tokens(node):
    """Every token that counts as 'a form of this verb' for drill matching."""
    forms = set()
    for tense in V2_TENSES:
        for cell in node.get("table", {}).get(tense, {}).values():
            forms.update(tokenize(cell["formal"]))
            if "street" in cell:
                forms.update(tokenize(cell["street"]))
    forms.update(tokenize(node.get("infinitive", "")))
    forms.update(tokenize(node.get("participle", "")))
    forms -= {"je", "tu", "il", "on", "vous", "ils", "j", "t"}
    # être-aux compounds put suis/est/sont in the table; keep them — they are
    # legitimately part of the paradigm being drilled
    return forms


def validate_v2_conjugation(node, base_lex, report):
    """Returns kept drills. Structural problems -> errors; vocab -> warnings."""
    if node.get("family") == "politesse":
        form_tokens = set()
        for f in node.get("forms", []):
            form_tokens.update(tokenize(f["formal"]))
            form_tokens.update(tokenize(f["street"]))
        if not node.get("forms"):
            report["errors"].append(f"{node['id']}: politesse node has no forms")
    else:
        for tense in V2_TENSES:
            missing = [p for p in V2_PERSONS if not node.get("table", {}).get(tense, {}).get(p, {}).get("formal")]
            if missing:
                report["errors"].append(f"{node['id']}: table {tense} missing persons {missing}")
        form_tokens = verb_form_tokens(node)

    kept = []
    extra = form_tokens | set()
    for d in node.get("drills", []):
        problems = check_drill_fields(d, node["id"])
        toks = set(tokenize(d["french_formal"])) | set(tokenize(d["french_street"]))
        if form_tokens and not toks & form_tokens:
            problems.append("no form of the target verb in the French text")
        if problems:
            report["dropped"].append({"id": d.get("id", "?"), "reasons": problems,
                                      "french_formal": d.get("french_formal", "")})
            continue
        unk = unknown_tokens(d, base_lex, extra)
        if unk:
            report["warnings"].append(f"{d['id']}: vocabulary outside known set: {unk}")
        kept.append(d)
    if len(kept) < 15 and node.get("family") != "politesse":
        report["errors"].append(f"{node['id']}: only {len(kept)} valid drills (need >= 15) — regenerate with --force")
    return kept


def validate_v2_vocab(node, base_lex, report):
    words = node.get("words", [])
    if len(words) != 25:
        report["errors"].append(f"{node['id']}: {len(words)} words (expected 25)")
    for w in words:
        if not w.get("lemma", "").strip() or not w.get("english", "").strip():
            report["errors"].append(f"{node['id']}: word {w.get('id')} missing lemma/gloss")

    kept = []
    pack_lemmas = {w["lemma"] for w in words}
    for d in node.get("drills", []):
        problems = check_drill_fields(d, node["id"])
        toks = set(tokenize(d["french_formal"])) | set(tokenize(d["french_street"]))
        claimed = [w for w in d.get("target_words", []) if w in pack_lemmas]
        if not any(lemma_in_text(w, toks) for w in claimed):
            problems.append("no claimed pack word found in the French text")
        if problems:
            report["dropped"].append({"id": d.get("id", "?"), "reasons": problems,
                                      "french_formal": d.get("french_formal", "")})
            continue
        unk = unknown_tokens(d, base_lex, pack_lemmas)
        if unk:
            report["warnings"].append(f"{d['id']}: vocabulary outside known set: {unk}")
        kept.append(d)

    for w in words:
        n = sum(1 for d in kept
                if lemma_in_text(w["lemma"], set(tokenize(d["french_formal"])) | set(tokenize(d["french_street"]))))
        if n < 2:
            report["errors"].append(f"{node['id']}: '{w['lemma']}' covered by {n} drill(s) "
                                    f"(need >= 2) — regenerate with --force")
    return kept


def validate_v2_grammar(node, base_lex, report):
    n_words = len(node.get("explanation", "").split())
    if n_words > 260:
        report["errors"].append(f"{node['id']}: explanation {n_words} words (spec <= 200)")
    elif n_words > 200:
        report["warnings"].append(f"{node['id']}: explanation {n_words} words (spec <= 200)")
    n_ex = len(node.get("canonical_examples", []))
    if not 6 <= n_ex <= 8:
        report["errors"].append(f"{node['id']}: {n_ex} canonical examples (spec 6-8)")
    example_tokens = set()
    for ex in node.get("canonical_examples", []):
        for field in ("english", "formal", "street"):
            if not ex.get(field, "").strip():
                report["errors"].append(f"{node['id']}: canonical example missing {field}")
        example_tokens.update(tokenize(ex.get("formal", "")))
        example_tokens.update(tokenize(ex.get("street", "")))

    kept = []
    for d in node.get("drills", []):
        problems = check_drill_fields(d, node["id"])
        if problems:
            report["dropped"].append({"id": d.get("id", "?"), "reasons": problems,
                                      "french_formal": d.get("french_formal", "")})
            continue
        unk = unknown_tokens(d, base_lex, example_tokens)
        if unk:
            report["warnings"].append(f"{d['id']}: vocabulary outside known set: {unk}")
        kept.append(d)
    if len(kept) < 18:
        report["errors"].append(f"{node['id']}: only {len(kept)} valid drills (spec 20) — regenerate with --force")
    return kept


def validate_v2(strict):
    with open(HERE / "graph.json") as f:
        graph = json.load(f)
    graph_errors = validate_graph(graph)
    if graph_errors:
        print("V1 GRAPH ERRORS:")
        for e in graph_errors:
            print(f"  - {e}")
        sys.exit(1)

    checkers = {"conjugation": validate_v2_conjugation,
                "vocab": validate_v2_vocab,
                "grammar": validate_v2_grammar}
    base_lex = v2_base_lexicon(graph["nodes"])
    full_report, any_errors = {}, False
    all_v2_nodes = []
    module_data = {}
    for module in V2_MODULES:
        data = load_v2_module(module)
        if data is None:
            print(f"learn_{module}.json not found — skipped")
            continue
        module_data[module] = data
        all_v2_nodes.extend(data["nodes"])

    dag_errors = validate_v2_dag(graph["nodes"], all_v2_nodes)
    if dag_errors:
        any_errors = True
        print("V2 DAG ERRORS:")
        for e in dag_errors:
            print(f"  - {e}")
    elif all_v2_nodes:
        print(f"combined DAG OK ({len(graph['nodes'])} v1 + {len(all_v2_nodes)} v2 nodes)")

    for module, data in module_data.items():
        report = {"errors": [], "warnings": [], "dropped": []}
        validated_nodes = []
        drills_kept = 0
        for node in data["nodes"]:
            kept = checkers[module](node, base_lex, report)
            vn = dict(node)
            vn["drills"] = kept
            drills_kept += len(kept)
            validated_nodes.append(vn)

        out_path = HERE / f"learn_{module}_validated.json"
        with open(out_path, "w") as f:
            json.dump({"version": data.get("version", 2), "nodes": validated_nodes},
                      f, ensure_ascii=False, indent=2)

        full_report[module] = {
            "nodes": len(validated_nodes),
            "drills_kept": drills_kept,
            "drills_dropped": len(report["dropped"]),
            **report,
        }
        any_errors = any_errors or bool(report["errors"])
        print(f"{module}: {len(validated_nodes)} nodes, {drills_kept} drills kept, "
              f"{len(report['dropped'])} dropped, {len(report['errors'])} errors, "
              f"{len(report['warnings'])} warnings -> {out_path.name}")
        for e in report["errors"][:5]:
            print(f"  ERROR {e}")
        for w in report["warnings"][:5]:
            print(f"  warn  {w}")

    full_report["dag_errors"] = dag_errors
    with open(HERE / "validation_report_v2.json", "w") as f:
        json.dump(full_report, f, ensure_ascii=False, indent=2)
    print("full detail in validation_report_v2.json")
    if any_errors and strict:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="exit 1 on any rejection")
    ap.add_argument("--v2", action="store_true",
                    help="validate v2 Learn content (learn_*.json) instead of v1 sentences")
    ap.add_argument("--sentences", default=HERE / "sentences.json", type=Path)
    args = ap.parse_args()

    if args.v2:
        validate_v2(args.strict)
        return

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
