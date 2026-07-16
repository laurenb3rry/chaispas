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


# Phase 10b voice lint: hype metaphors the voice spec bans outright.
BANNED_VOICE = re.compile(
    r"\b(weaponiz\w*|unfair advantage|vip|superpowers?|game.?changers?|magic\w*"
    r"|secret weapons?|cheat codes?|hacks?)\b", re.IGNORECASE)

# Structured explanation budgets (phase 10b): (min_sections, max_sections,
# warn-above/below word bounds, hard error ceiling). Bands sit above the
# prompt targets (160 / 320) because the model reliably overshoots ~20%.
EXPLANATION_BUDGETS = {
    "verb": (2, 4, (None, 200), 260),
    "grammar": (4, 7, (170, 380), 480),
}


def explanation_text(sections):
    parts = []
    for s in sections:
        parts.append(str(s.get("header", "")))
        parts.append(str(s.get("body", "")))
        parts.extend(str(b) for b in s.get("bullets") or [])
    return " ".join(parts)


def validate_explanation(node, kind, report):
    """Phase 10b: explanations are ordered section arrays in a plain expert
    voice. Shape problems and banned phrases are errors; budget drift warns."""
    nid = node["id"]
    sections = node.get("explanation")
    if not isinstance(sections, list) or not sections:
        report["errors"].append(f"{nid}: explanation must be a non-empty section array")
        return
    n_lo, n_hi, (w_lo, w_hi), w_err = EXPLANATION_BUDGETS[kind]
    if not n_lo <= len(sections) <= n_hi:
        report["warnings"].append(
            f"{nid}: {len(sections)} explanation sections (spec {n_lo}-{n_hi})")
    for i, s in enumerate(sections, 1):
        if not str(s.get("header", "")).strip() or not str(s.get("body", "")).strip():
            report["errors"].append(f"{nid}: explanation section {i} missing header/body")
        for pair in s.get("examples") or []:
            if not str(pair.get("french", "")).strip() or not str(pair.get("english", "")).strip():
                report["errors"].append(
                    f"{nid}: explanation section {i} example missing french/english")
    words = len(explanation_text(sections).split())
    if words > w_err:
        report["errors"].append(f"{nid}: explanation {words} words (hard cap {w_err})")
    elif (w_hi and words > w_hi) or (w_lo and words < w_lo):
        report["warnings"].append(
            f"{nid}: explanation {words} words (spec {w_lo or 0}-{w_hi})")
    banned = sorted({m.group(0).lower() for m in BANNED_VOICE.finditer(explanation_text(sections))})
    if banned:
        report["errors"].append(f"{nid}: banned voice phrases {banned} — regenerate")


def validate_tense_usage(data, report):
    """The conjugation file carries shared tense-usage guidance (phase 10b)."""
    usage = data.get("tense_usage")
    if not isinstance(usage, dict):
        report["errors"].append("conjugation: missing top-level tense_usage")
        return
    for tense in V2_TENSES:
        entry = usage.get(tense)
        if not entry or not str(entry.get("note", "")).strip() \
                or not str(entry.get("label", "")).strip():
            report["errors"].append(f"tense_usage.{tense}: missing label/note")
            continue
        contrasts = entry.get("contrasts") or []
        if not 2 <= len(contrasts) <= 3:
            report["warnings"].append(
                f"tense_usage.{tense}: {len(contrasts)} contrasts (spec 2-3)")
        for i, c in enumerate(contrasts, 1):
            for field in ("a_french", "a_english", "b_french", "b_english", "point"):
                if not str(c.get(field, "")).strip():
                    report["errors"].append(f"tense_usage.{tense} contrast {i}: missing {field}")


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
    validate_explanation(node, "verb", report)
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
    validate_explanation(node, "grammar", report)
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
        if module == "conjugation":
            validate_tense_usage(data, report)
        for node in data["nodes"]:
            kept = checkers[module](node, base_lex, report)
            vn = dict(node)
            vn["drills"] = kept
            drills_kept += len(kept)
            validated_nodes.append(vn)

        out_path = HERE / f"learn_{module}_validated.json"
        # carry every top-level key through (tense_usage rides with conjugation)
        validated = {k: v for k, v in data.items() if k != "nodes"}
        validated.setdefault("version", 2)
        validated["nodes"] = validated_nodes
        with open(out_path, "w") as f:
            json.dump(validated, f, ensure_ascii=False, indent=2)

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


# ---------------------------------------------------------------------------
# v2b validation (PLAN2 §3.4-3.5, phase 6): Speak scenarios and Listen
# episodes. Same philosophy as v2 Learn: structural problems are errors
# (demand regeneration), vocabulary drift is warn-level. Granularity is the
# whole scenario / episode — a unit with any error is excluded from the
# validated output so TTS never voices broken content.

# Nodes on every start->end path. PLAN2's "8-14 exchanges" read as npc+user
# pairs (~2 nodes each) — one-line-per-exchange forced unnaturally clipped
# dialogues in practice — with grace at the bottom for reconverging branch paths.
SCN_PATH_RANGE = (12, 28)
SCN_BRANCH_RANGE = (2, 3)    # branch points per variant


def collect_french_strings(obj, out):
    """All French text in a generated-content JSON tree (for lexicon building)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and k in ("formal", "street", "french_formal",
                                            "french_street", "lemma"):
                out.append(v)
            else:
                collect_french_strings(v, out)
    elif isinstance(obj, list):
        for x in obj:
            collect_french_strings(x, out)


def v2b_lexicon(v1_nodes):
    """v2 base lexicon plus everything the Learn module already teaches —
    scenario/episode vocab checks warn relative to the whole curriculum."""
    lex = v2_base_lexicon(v1_nodes)
    for module in V2_MODULES:
        path = HERE / f"learn_{module}_validated.json"
        if not path.exists():
            path = HERE / f"learn_{module}.json"
        if not path.exists():
            continue
        strings = []
        with open(path) as f:
            collect_french_strings(json.load(f), strings)
        for s in strings:
            lex.update(tokenize(s))
    return lex


def walk_variant(nodes_by_id, start_id, errors, prefix):
    """DFS the branching dialogue. Returns (path lengths, reachable node ids)."""
    lengths, reachable = [], set()

    def walk(nid, seen, depth):
        if depth > 30:
            errors.append(f"{prefix}: path deeper than 30 nodes — runaway graph")
            return
        node = nodes_by_id.get(nid)
        if node is None:
            errors.append(f"{prefix}: reference to unknown node '{nid}'")
            return
        if nid in seen:
            errors.append(f"{prefix}: cycle through '{nid}'")
            return
        reachable.add(nid)
        if node.get("branches"):
            nexts = [b.get("next") for b in node["branches"]]
        else:
            nexts = [node.get("next")]
        for nx in nexts:
            if nx is None:
                lengths.append(depth + 1)
            else:
                walk(nx, seen | {nid}, depth + 1)

    walk(start_id, set(), 0)
    return lengths, reachable


def validate_v2b_variant(variant, lex, report):
    vid = variant.get("variant_id", "?")
    nodes = variant.get("nodes", [])
    if not nodes:
        report["errors"].append(f"{vid}: no nodes")
        return
    ids = [n.get("node_id") for n in nodes]
    if len(ids) != len(set(ids)):
        report["errors"].append(f"{vid}: duplicate node ids")
    nodes_by_id = {n["node_id"]: n for n in nodes}

    for n in nodes:
        nid = n.get("node_id", "?")
        if n.get("speaker") not in ("npc", "user"):
            report["errors"].append(f"{nid}: bad speaker '{n.get('speaker')}'")
        for field in ("english", "french_street"):
            if not str(n.get(field, "")).strip():
                report["errors"].append(f"{nid}: empty {field}")
        if n.get("speaker") == "user" and not str(n.get("french_formal", "")).strip():
            report["warnings"].append(f"{nid}: user node missing french_formal")
        if n.get("branches"):
            if n.get("next"):
                report["errors"].append(f"{nid}: has both 'next' and 'branches'")
            if n.get("speaker") != "npc":
                report["warnings"].append(f"{nid}: branch point on a user node")
            if not SCN_BRANCH_RANGE[0] <= len(n["branches"]) <= SCN_BRANCH_RANGE[1]:
                report["errors"].append(f"{nid}: {len(n['branches'])} branch options (spec 2-3)")
            for b in n["branches"]:
                if not str(b.get("label_english", "")).strip():
                    report["errors"].append(f"{nid}: branch option missing label_english")
        unk = sorted({t for t in tokenize(n.get("french_street", "")) +
                      tokenize(n.get("french_formal", ""))
                      if not in_lexicon(t, lex) and not COGNATE.match(t)
                      and not t.isdigit()})
        if unk:
            report["warnings"].append(f"{nid}: vocabulary outside known set: {unk}")

    lengths, reachable = walk_variant(nodes_by_id, nodes[0]["node_id"], report["errors"], vid)
    unreachable = set(nodes_by_id) - reachable
    if unreachable:
        report["errors"].append(f"{vid}: unreachable nodes {sorted(unreachable)}")
    if lengths and not (SCN_PATH_RANGE[0] <= min(lengths) and max(lengths) <= SCN_PATH_RANGE[1]):
        report["errors"].append(f"{vid}: path lengths {min(lengths)}-{max(lengths)} "
                                f"(spec {SCN_PATH_RANGE[0]}-{SCN_PATH_RANGE[1]})")
    n_branch = sum(1 for n in nodes if n.get("branches"))
    if not SCN_BRANCH_RANGE[0] <= n_branch <= SCN_BRANCH_RANGE[1]:
        report["errors"].append(f"{vid}: {n_branch} branch points "
                                f"(spec {SCN_BRANCH_RANGE[0]}-{SCN_BRANCH_RANGE[1]})")
    n_user = sum(1 for n in nodes if n.get("speaker") == "user")
    if n_user < 4:
        report["warnings"].append(f"{vid}: only {n_user} user turns")


def validate_v2b_scenario(scn, lex, report):
    sid = scn.get("id", "?")
    for field in ("id", "title", "icon", "setting_blurb", "difficulty"):
        if scn.get(field) in (None, ""):
            report["errors"].append(f"{sid}: missing scenario field '{field}'")
    variants = scn.get("variants", [])
    if len(variants) != 3:
        report["errors"].append(f"{sid}: {len(variants)} variants (spec 3) — "
                                f"finish generation before validating")
    for v in variants:
        validate_v2b_variant(v, lex, report)


def validate_v2b_episode(ep, lex, report):
    from gen_listen import LEVELS
    eid = ep.get("id", "?")
    level = LEVELS.get(ep.get("level"))
    if level is None:
        report["errors"].append(f"{eid}: unknown level '{ep.get('level')}'")
        return

    speakers = ep.get("speakers", [])
    if len(speakers) != 2 or any(not s.get("label") or not s.get("voice") for s in speakers):
        report["errors"].append(f"{eid}: needs exactly 2 speakers with label+voice")
    elif speakers[0]["voice"] == speakers[1]["voice"]:
        report["errors"].append(f"{eid}: both speakers use the same voice")

    lines = ep.get("lines", [])
    lo, hi = level["lines"]
    if not lo - 2 <= len(lines) <= hi + 3:
        report["errors"].append(f"{eid}: {len(lines)} lines (level {ep['level']} spec {lo}-{hi})")
    elif not lo <= len(lines) <= hi:
        report["warnings"].append(f"{eid}: {len(lines)} lines (level {ep['level']} spec {lo}-{hi})")
    clo, chi = level["chars"]
    total_chars = sum(len(l.get("french_street", "")) for l in lines)
    if not clo * 0.7 <= total_chars <= chi * 1.3:
        report["warnings"].append(f"{eid}: {total_chars} French chars "
                                  f"(level {ep['level']} target {clo}-{chi})")

    extra = set()
    for s in speakers:
        extra.update(tokenize(s.get("label", "")))
    extra.update(tokenize(ep.get("title", "")))
    used_speakers, doubles = set(), 0
    prev = None
    for l in lines:
        lid = l.get("line_id", "?")
        if l.get("speaker") not in (1, 2):
            report["errors"].append(f"{lid}: bad speaker '{l.get('speaker')}'")
        used_speakers.add(l.get("speaker"))
        if l.get("speaker") == prev:
            doubles += 1
        prev = l.get("speaker")
        for field in ("french_street", "english"):
            if not str(l.get(field, "")).strip():
                report["errors"].append(f"{lid}: empty {field}")
        unk = sorted({t for t in tokenize(l.get("french_street", ""))
                      if not in_lexicon(t, lex) and not in_lexicon(t, extra)
                      and not COGNATE.match(t) and not t.isdigit()})
        if unk:
            report["warnings"].append(f"{lid}: vocabulary outside known set: {unk}")
    if len(used_speakers - {None}) < 2:
        report["errors"].append(f"{eid}: only one speaker ever talks")
    if doubles > 2:
        report["warnings"].append(f"{eid}: {doubles} consecutive same-speaker turns")

    questions = ep.get("questions", [])
    if len(questions) != 3:
        report["errors"].append(f"{eid}: {len(questions)} questions (spec 3)")
    answer_positions = set()
    for i, q in enumerate(questions, 1):
        if not str(q.get("question", "")).strip():
            report["errors"].append(f"{eid} q{i}: empty question")
        opts = q.get("options", [])
        if len(opts) != 4 or any(not str(o).strip() for o in opts):
            report["errors"].append(f"{eid} q{i}: needs exactly 4 non-empty options")
        if not isinstance(q.get("answer_index"), int) or not 0 <= q["answer_index"] <= 3:
            report["errors"].append(f"{eid} q{i}: bad answer_index {q.get('answer_index')}")
        else:
            answer_positions.add(q["answer_index"])
    if len(questions) == 3 and len(answer_positions) == 1:
        report["warnings"].append(f"{eid}: all correct answers at position "
                                  f"{answer_positions.pop()}")


def validate_v2b(strict):
    with open(HERE / "graph.json") as f:
        graph = json.load(f)
    base_lex = v2b_lexicon(graph["nodes"])
    full_report, any_errors = {}, False

    sections = [
        ("scenarios", HERE / "scenarios.json", "scenarios", validate_v2b_scenario,
         lambda u: f"{len(u.get('variants', []))} variants"),
        ("listen", HERE / "listen.json", "episodes", validate_v2b_episode,
         lambda u: f"level {u.get('level')}, {len(u.get('lines', []))} lines"),
    ]
    for name, path, key, checker, describe in sections:
        if not path.exists():
            print(f"{path.name} not found — skipped")
            continue
        with open(path) as f:
            data = json.load(f)
        report = {"errors": [], "warnings": []}
        kept, failed = [], []
        for unit in data[key]:
            before = len(report["errors"])
            checker(unit, base_lex, report)
            if len(report["errors"]) == before:
                kept.append(unit)
            else:
                failed.append(unit.get("id", "?"))

        out_path = HERE / f"{name}_validated.json"
        with open(out_path, "w") as f:
            json.dump({"version": data.get("version", 2), key: kept},
                      f, ensure_ascii=False, indent=2)

        full_report[name] = {"units_kept": len(kept), "units_failed": failed, **report}
        any_errors = any_errors or bool(report["errors"])
        print(f"{name}: {len(kept)}/{len(data[key])} units kept, "
              f"{len(report['errors'])} errors, {len(report['warnings'])} warnings "
              f"-> {out_path.name}")
        if failed:
            print(f"  failed units (regenerate with --force): {failed}")
        for e in report["errors"][:5]:
            print(f"  ERROR {e}")
        for w in report["warnings"][:5]:
            print(f"  warn  {w}")

    with open(HERE / "validation_report_v2b.json", "w") as f:
        json.dump(full_report, f, ensure_ascii=False, indent=2)
    print("full detail in validation_report_v2b.json")
    if any_errors and strict:
        sys.exit(1)


# ---------------------------------------------------------------------------
# v2c validation (PLAN2 §3.6, phase 7): Read passages. Structural problems are
# errors (a passage with any error is excluded from the validated output);
# gloss keys that don't appear in the body are pruned with a warning. Unlike
# the other modes there is no unknown-vocab warning pass — Read is explicitly
# wide-exposure content and the gloss map is the safety net; what gets checked
# instead is that the gloss actually covers the passage's content words.
# Style diversity (max 8 passages per style) is checked file-level per plan.

MAX_PER_STYLE = 8
READ_HARD_WORDS = (50, 230)   # spec 60-200 plus generation grace
GLOSS_COVERAGE_ERROR = 0.50   # below: regenerate
GLOSS_COVERAGE_WARN = 0.80
CAPITALIZED = re.compile(r"[A-ZÀ-Ý][\wà-ÿ'’-]*")


def gloss_coverage(body, gloss):
    """Share of the body's content tokens covered by some gloss key.
    Proper-noun-looking (capitalized) and digit-bearing tokens are exempt —
    a filter, not a proof (sentence-initial words ride along as exempt)."""
    covered = set()
    for k in gloss:
        covered.update(tokenize(k))
    exempt = set()
    for m in CAPITALIZED.finditer(body):
        exempt.update(tokenize(m.group(0)))
    content = [t for t in tokenize(body)
               if t not in FUNCTION_WORDS and t not in exempt
               and len(t) > 1 and not any(c.isdigit() for c in t)]
    if not content:
        return 1.0, []
    missed = [t for t in content if t not in covered]
    return 1 - len(missed) / len(content), sorted(set(missed))


def validate_v2c_passage(p, report):
    from gen_read import STYLES, TIERS, count_words
    pid = p.get("id", "?")
    for field in ("id", "title", "style", "body", "gloss", "questions"):
        if not p.get(field):
            report["errors"].append(f"{pid}: missing/empty '{field}'")
    if p.get("style") not in STYLES:
        report["errors"].append(f"{pid}: unknown style '{p.get('style')}'")
    tier = p.get("tier")
    if tier not in TIERS:
        report["errors"].append(f"{pid}: bad tier {tier!r}")
        return

    body = p.get("body", "")
    words = count_words(body)
    lo, hi = TIERS[tier]["words"]
    if not READ_HARD_WORDS[0] <= words <= READ_HARD_WORDS[1]:
        report["errors"].append(f"{pid}: {words} words (hard bounds "
                                f"{READ_HARD_WORDS[0]}-{READ_HARD_WORDS[1]})")
    elif not lo <= words <= hi:
        report["warnings"].append(f"{pid}: {words} words (tier {tier} target {lo}-{hi})")

    gloss = p.get("gloss", {})
    if isinstance(gloss, dict) and gloss:
        body_norm = norm(body).replace("’", "'")
        stale = [k for k in gloss if norm(k) not in body_norm]
        if stale:
            report["warnings"].append(f"{pid}: gloss keys not found in body "
                                      f"(pruned): {stale}")
            for k in stale:
                del gloss[k]
        coverage, missed = gloss_coverage(body, gloss)
        if coverage < GLOSS_COVERAGE_ERROR:
            report["errors"].append(f"{pid}: gloss covers only {coverage:.0%} of content "
                                    f"words — regenerate with --force (missed: {missed[:10]})")
        elif coverage < GLOSS_COVERAGE_WARN:
            report["warnings"].append(f"{pid}: gloss coverage {coverage:.0%} "
                                      f"(missed: {missed[:10]})")

    questions = p.get("questions", [])
    if not 2 <= len(questions) <= 3:
        report["errors"].append(f"{pid}: {len(questions)} questions (spec 2-3)")
    answer_positions = set()
    for i, q in enumerate(questions, 1):
        if not str(q.get("question", "")).strip():
            report["errors"].append(f"{pid} q{i}: empty question")
        opts = q.get("options", [])
        if len(opts) != 4 or any(not str(o).strip() for o in opts):
            report["errors"].append(f"{pid} q{i}: needs exactly 4 non-empty options")
        if not isinstance(q.get("answer_index"), int) or not 0 <= q["answer_index"] <= 3:
            report["errors"].append(f"{pid} q{i}: bad answer_index {q.get('answer_index')}")
        else:
            answer_positions.add(q["answer_index"])
    if len(questions) >= 2 and len(answer_positions) == 1:
        report["warnings"].append(f"{pid}: all correct answers at position "
                                  f"{answer_positions.pop()}")


def validate_v2c(strict):
    path = HERE / "read.json"
    if not path.exists():
        print("read.json not found — nothing to validate")
        return
    with open(path) as f:
        data = json.load(f)
    passages = data["passages"]

    report = {"errors": [], "warnings": []}
    ids = [p.get("id") for p in passages]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        report["errors"].append(f"duplicate passage ids: {sorted(dupes)}")

    kept, failed = [], []
    for p in passages:
        before = len(report["errors"])
        validate_v2c_passage(p, report)
        if len(report["errors"]) == before:
            kept.append(p)
        else:
            failed.append(p.get("id", "?"))

    style_counts, tier_counts = {}, {}
    for p in kept:
        style_counts[p["style"]] = style_counts.get(p["style"], 0) + 1
        tier_counts[p["tier"]] = tier_counts.get(p["tier"], 0) + 1
    over = {s: n for s, n in style_counts.items() if n > MAX_PER_STYLE}
    if over:
        report["errors"].append(f"style diversity violated (max {MAX_PER_STYLE} "
                                f"per style): {over}")

    out_path = HERE / "read_validated.json"
    with open(out_path, "w") as f:
        json.dump({"version": data.get("version", 2), "passages": kept},
                  f, ensure_ascii=False, indent=2)

    full_report = {"passages_kept": len(kept), "passages_failed": failed,
                   "by_style": dict(sorted(style_counts.items())),
                   "by_tier": {str(t): n for t, n in sorted(tier_counts.items())},
                   **report}
    with open(HERE / "validation_report_v2c.json", "w") as f:
        json.dump(full_report, f, ensure_ascii=False, indent=2)

    print(f"read: {len(kept)}/{len(passages)} passages kept, "
          f"{len(report['errors'])} errors, {len(report['warnings'])} warnings "
          f"-> {out_path.name}")
    print(f"  by style: {full_report['by_style']}")
    print(f"  by tier:  {full_report['by_tier']}")
    if failed:
        print(f"  failed passages (regenerate with --force): {failed}")
    for e in report["errors"][:5]:
        print(f"  ERROR {e}")
    for w in report["warnings"][:5]:
        print(f"  warn  {w}")
    print("full detail in validation_report_v2c.json")
    if report["errors"] and strict:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="exit 1 on any rejection")
    ap.add_argument("--v2", action="store_true",
                    help="validate v2 Learn content (learn_*.json) instead of v1 sentences")
    ap.add_argument("--v2b", action="store_true",
                    help="validate Speak scenarios + Listen episodes (scenarios.json, listen.json)")
    ap.add_argument("--v2c", action="store_true",
                    help="validate Read passages (read.json)")
    ap.add_argument("--sentences", default=HERE / "sentences.json", type=Path)
    args = ap.parse_args()

    if args.v2c:
        validate_v2c(args.strict)
        return
    if args.v2b:
        validate_v2b(args.strict)
        return
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
