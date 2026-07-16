#!/usr/bin/env python3
"""Phase 10b: append the 29 approved expansion verbs to data/verbs.json.

Hand-authored paradigms (présent + imparfait stem + participle/aux), same
shape as the original 20. Idempotent: skips verbs already present.
Tiers extend the frequency bands: adopted ranks 21-30 → tier 4,
31-40 → tier 5, 41-49 → tier 6.

Run once:  python data/verbs_10b_additions.py
"""

import json
from pathlib import Path

VERBS_PATH = Path(__file__).parent / "verbs.json"

# fields: infinitive, english, family, rank, aux, participle, je_reduction,
#         present {je,tu,il,on,vous,ils}, imparfait_stem, street_notes
NEW_VERBS = [
    {
        "infinitive": "croire", "english": "to believe / to think", "family": "irregular",
        "rank": 21, "aux": "avoir", "participle": "cru", "je_reduction": True,
        "present": {"je": "crois", "tu": "crois", "il": "croit", "on": "croit",
                    "vous": "croyez", "ils": "croient"},
        "imparfait_stem": "croy",
        "street_notes": "j'crois is one of the most common sentence-starters in spoken French — j'crois pas, j'crois que oui. tu crois → t'crois in fast speech.",
    },
    {
        "infinitive": "penser", "english": "to think", "family": "er_regular",
        "rank": 22, "aux": "avoir", "participle": "pensé", "je_reduction": True,
        "present": {"je": "pense", "tu": "penses", "il": "pense", "on": "pense",
                    "vous": "pensez", "ils": "pensent"},
        "imparfait_stem": "pens",
        "street_notes": "j'pense is the everyday opinion opener — j'pense que c'est bon. penser à quelqu'un = think about; penser que = think that.",
    },
    {
        "infinitive": "passer", "english": "to pass / to stop by", "family": "er_regular",
        "rank": 23, "aux": "être", "participle": "passé", "je_reduction": True,
        "present": {"je": "passe", "tu": "passes", "il": "passe", "on": "passe",
                    "vous": "passez", "ils": "passent"},
        "imparfait_stem": "pass",
        "street_notes": "je suis passé = I stopped by (être when moving); j'ai passé une bonne soirée (avoir when it takes an object). j'passe te voir = I'll drop in on you. ça passe = it's acceptable / it fits.",
    },
    {
        "infinitive": "arriver", "english": "to arrive / to manage / to happen", "family": "er_regular",
        "rank": 24, "aux": "être", "participle": "arrivé", "je_reduction": False,
        "present": {"je": "arrive", "tu": "arrives", "il": "arrive", "on": "arrive",
                    "vous": "arrivez", "ils": "arrivent"},
        "imparfait_stem": "arriv",
        "street_notes": "j'arrive ! = coming! — said constantly. ça arrive = it happens / no big deal. j'arrive pas à... = I can't manage to... (the everyday 'I can't').",
    },
    {
        "infinitive": "rester", "english": "to stay", "family": "er_regular",
        "rank": 25, "aux": "être", "participle": "resté", "je_reduction": True,
        "present": {"je": "reste", "tu": "restes", "il": "reste", "on": "reste",
                    "vous": "restez", "ils": "restent"},
        "imparfait_stem": "rest",
        "street_notes": "false friend: rester = stay, never 'rest'. j'reste là = I'm staying here. il reste... = there's ... left (il en reste ? = is there any left?).",
    },
    {
        "infinitive": "aider", "english": "to help", "family": "er_regular",
        "rank": 26, "aux": "avoir", "participle": "aidé", "je_reduction": False,
        "present": {"je": "aide", "tu": "aides", "il": "aide", "on": "aide",
                    "vous": "aidez", "ils": "aident"},
        "imparfait_stem": "aid",
        "street_notes": "j'aide by formal elision. tu aides → t'aides. Direct object, no preposition: tu peux m'aider ? = can you help me?",
    },
    {
        "infinitive": "regarder", "english": "to watch / to look at", "family": "er_regular",
        "rank": 27, "aux": "avoir", "participle": "regardé", "je_reduction": True,
        "present": {"je": "regarde", "tu": "regardes", "il": "regarde", "on": "regarde",
                    "vous": "regardez", "ils": "regardent"},
        "imparfait_stem": "regard",
        "street_notes": "no 'at': regarder quelque chose directly — j'regarde la télé. regarde ! alone = look! — constant between friends.",
    },
    {
        "infinitive": "trouver", "english": "to find", "family": "er_regular",
        "rank": 28, "aux": "avoir", "participle": "trouvé", "je_reduction": True,
        "present": {"je": "trouve", "tu": "trouves", "il": "trouve", "on": "trouve",
                    "vous": "trouvez", "ils": "trouvent"},
        "imparfait_stem": "trouv",
        "street_notes": "j'trouve que... = I find/think that... — the second opinion frame after j'crois. tu trouves ? = you think so? j'trouve pas = I don't think so / can't find it.",
    },
    {
        "infinitive": "attendre", "english": "to wait (for)", "family": "re_regular",
        "rank": 29, "aux": "avoir", "participle": "attendu", "je_reduction": False,
        "present": {"je": "attends", "tu": "attends", "il": "attend", "on": "attend",
                    "vous": "attendez", "ils": "attendent"},
        "imparfait_stem": "attend",
        "street_notes": "j'attends is already elided in formal French; tu attends → t'attends. Attends ! alone is the universal 'hang on'. attendre takes its object with no preposition — j'attends le bus, never 'pour'.",
    },
    {
        "infinitive": "appeler", "english": "to call", "family": "er_spelling",
        "rank": 30, "aux": "avoir", "participle": "appelé", "je_reduction": False,
        "present": {"je": "appelle", "tu": "appelles", "il": "appelle", "on": "appelle",
                    "vous": "appelez", "ils": "appellent"},
        "imparfait_stem": "appel",
        "street_notes": "double-l where the ending is silent (j'appelle), single l where it's pronounced (vous appelez). j'appelle = I'll call — présent does the near future. je t'appelle = I'll call you.",
    },
    {
        "infinitive": "connaître", "english": "to know (people, places)", "family": "irregular",
        "rank": 31, "aux": "avoir", "participle": "connu", "je_reduction": True,
        "present": {"je": "connais", "tu": "connais", "il": "connaît", "on": "connaît",
                    "vous": "connaissez", "ils": "connaissent"},
        "imparfait_stem": "connaiss",
        "street_notes": "connaître = know people/places/things by acquaintance; savoir = know facts/how-to. j'connais pas = don't know it/them. tu connais ? = you know it? — the recommendation opener.",
    },
    {
        "infinitive": "porter", "english": "to wear / to carry", "family": "er_regular",
        "rank": 32, "aux": "avoir", "participle": "porté", "je_reduction": True,
        "present": {"je": "porte", "tu": "portes", "il": "porte", "on": "porte",
                    "vous": "portez", "ils": "portent"},
        "imparfait_stem": "port",
        "street_notes": "wear and carry are the same verb — context decides. j'porte jamais de noir = I never wear black. ça se porte = people wear that.",
    },
    {
        "infinitive": "sortir", "english": "to go out / to leave", "family": "partir_family",
        "rank": 33, "aux": "être", "participle": "sorti", "je_reduction": True,
        "present": {"je": "sors", "tu": "sors", "il": "sort", "on": "sort",
                    "vous": "sortez", "ils": "sortent"},
        "imparfait_stem": "sort",
        "street_notes": "same shape as partir: sors/sort split. on sort ce soir ? = we going out tonight? je suis sorti hier = I went out last night. sortir avec quelqu'un = to date someone.",
    },
    {
        "infinitive": "comprendre", "english": "to understand", "family": "prendre_family",
        "rank": 34, "aux": "avoir", "participle": "compris", "je_reduction": True,
        "present": {"je": "comprends", "tu": "comprends", "il": "comprend", "on": "comprend",
                    "vous": "comprenez", "ils": "comprennent"},
        "imparfait_stem": "compren",
        "street_notes": "prendre with a prefix — same forms exactly. j'comprends pas = the survival phrase. compris ? / c'est compris = got it?",
    },
    {
        "infinitive": "entendre", "english": "to hear", "family": "re_regular",
        "rank": 35, "aux": "avoir", "participle": "entendu", "je_reduction": False,
        "present": {"je": "entends", "tu": "entends", "il": "entend", "on": "entend",
                    "vous": "entendez", "ils": "entendent"},
        "imparfait_stem": "entend",
        "street_notes": "attendre's twin — same -re shape. j'entends rien = I can't hear anything. entendre = hear (passive), écouter = listen (active).",
    },
    {
        "infinitive": "demander", "english": "to ask (for)", "family": "er_regular",
        "rank": 36, "aux": "avoir", "participle": "demandé", "je_reduction": True,
        "present": {"je": "demande", "tu": "demandes", "il": "demande", "on": "demande",
                    "vous": "demandez", "ils": "demandent"},
        "imparfait_stem": "demand",
        "street_notes": "false friend: demander = ask, not demand. No 'for': j'demande l'addition. demander à quelqu'un = ask someone. j'me demande = I wonder.",
    },
    {
        "infinitive": "chercher", "english": "to look for", "family": "er_regular",
        "rank": 37, "aux": "avoir", "participle": "cherché", "je_reduction": True,
        "present": {"je": "cherche", "tu": "cherches", "il": "cherche", "on": "cherche",
                    "vous": "cherchez", "ils": "cherchent"},
        "imparfait_stem": "cherch",
        "street_notes": "no 'for' — the searching is built in: j'cherche la gare = I'm looking for the station. The shop/directions opener: je cherche...",
    },
    {
        "infinitive": "laisser", "english": "to leave / to let", "family": "er_regular",
        "rank": 38, "aux": "avoir", "participle": "laissé", "je_reduction": True,
        "present": {"je": "laisse", "tu": "laisses", "il": "laisse", "on": "laisse",
                    "vous": "laissez", "ils": "laissent"},
        "imparfait_stem": "laiss",
        "street_notes": "laisse tomber = forget it / drop it — essential street chunk. laisse-moi... = let me... j'laisse un pourboire = I'm leaving a tip.",
    },
    {
        "infinitive": "écouter", "english": "to listen (to)", "family": "er_regular",
        "rank": 39, "aux": "avoir", "participle": "écouté", "je_reduction": False,
        "present": {"je": "écoute", "tu": "écoutes", "il": "écoute", "on": "écoute",
                    "vous": "écoutez", "ils": "écoutent"},
        "imparfait_stem": "écout",
        "street_notes": "no 'to': j'écoute la radio. écoute... at the start of a sentence = look,... / listen,... — the French discourse opener.",
    },
    {
        "infinitive": "perdre", "english": "to lose", "family": "re_regular",
        "rank": 40, "aux": "avoir", "participle": "perdu", "je_reduction": True,
        "present": {"je": "perds", "tu": "perds", "il": "perd", "on": "perd",
                    "vous": "perdez", "ils": "perdent"},
        "imparfait_stem": "perd",
        "street_notes": "third of the -re family. j'ai perdu mon téléphone — the traveler's sentence. je suis perdu = I'm lost (état, with être). c'est perdu = it's gone.",
    },
    {
        "infinitive": "tenir", "english": "to hold", "family": "venir_family",
        "rank": 41, "aux": "avoir", "participle": "tenu", "je_reduction": True,
        "present": {"je": "tiens", "tu": "tiens", "il": "tient", "on": "tient",
                    "vous": "tenez", "ils": "tiennent"},
        "imparfait_stem": "ten",
        "street_notes": "venir's shapes exactly, with avoir in the past. tiens ! = here you go / oh look — constant in handovers and surprise. tenir à = to care about.",
    },
    {
        "infinitive": "vivre", "english": "to live", "family": "irregular",
        "rank": 42, "aux": "avoir", "participle": "vécu", "je_reduction": True,
        "present": {"je": "vis", "tu": "vis", "il": "vit", "on": "vit",
                    "vous": "vivez", "ils": "vivent"},
        "imparfait_stem": "viv",
        "street_notes": "j'vis à Paris = I live in Paris — self-introduction core (habiter works too). j'ai vécu deux ans en France = I lived there two years — vécu for life chapters.",
    },
    {
        "infinitive": "essayer", "english": "to try", "family": "er_spelling",
        "rank": 43, "aux": "avoir", "participle": "essayé", "je_reduction": False,
        "present": {"je": "essaie", "tu": "essaies", "il": "essaie", "on": "essaie",
                    "vous": "essayez", "ils": "essaient"},
        "imparfait_stem": "essay",
        "street_notes": "y → i where the ending is silent (j'essaie), y kept where pronounced (vous essayez). essayer DE + infinitive: j'essaie d'apprendre. j'vais essayer = I'll try.",
    },
    {
        "infinitive": "travailler", "english": "to work", "family": "er_regular",
        "rank": 44, "aux": "avoir", "participle": "travaillé", "je_reduction": True,
        "present": {"je": "travaille", "tu": "travailles", "il": "travaille", "on": "travaille",
                    "vous": "travaillez", "ils": "travaillent"},
        "imparfait_stem": "travaill",
        "street_notes": "the small-talk verb: tu travailles où ? / j'travaille demain. Street synonyms you'll hear: bosser, taffer — recognize them, say travailler.",
    },
    {
        "infinitive": "rentrer", "english": "to go home / to get back", "family": "er_regular",
        "rank": 45, "aux": "être", "participle": "rentré", "je_reduction": True,
        "present": {"je": "rentre", "tu": "rentres", "il": "rentre", "on": "rentre",
                    "vous": "rentrez", "ils": "rentrent"},
        "imparfait_stem": "rentr",
        "street_notes": "'home' is built in: j'rentre = I'm heading home. tu rentres quand ? = when are you getting back? je suis rentré tard = I got home late (être).",
    },
    {
        "infinitive": "commencer", "english": "to start", "family": "er_regular",
        "rank": 46, "aux": "avoir", "participle": "commencé", "je_reduction": True,
        "present": {"je": "commence", "tu": "commences", "il": "commence", "on": "commence",
                    "vous": "commencez", "ils": "commencent"},
        "imparfait_stem": "commenç",
        "street_notes": "commencer À + infinitive: ça commence à m'énerver = it's starting to annoy me. ça commence quand ? = when does it start? (The ç spelling only shows up before a: je commençais.)",
    },
    {
        "infinitive": "oublier", "english": "to forget", "family": "er_regular",
        "rank": 47, "aux": "avoir", "participle": "oublié", "je_reduction": False,
        "present": {"je": "oublie", "tu": "oublies", "il": "oublie", "on": "oublie",
                    "vous": "oubliez", "ils": "oublient"},
        "imparfait_stem": "oubli",
        "street_notes": "j'ai oublié — the daily confession. j'oublie tout le temps = I always forget. oublie ! = forget it (sharper than laisse tomber).",
    },
    {
        "infinitive": "payer", "english": "to pay (for)", "family": "er_spelling",
        "rank": 48, "aux": "avoir", "participle": "payé", "je_reduction": True,
        "present": {"je": "paie", "tu": "paies", "il": "paie", "on": "paie",
                    "vous": "payez", "ils": "paient"},
        "imparfait_stem": "pay",
        "street_notes": "no 'for': j'paie le café = I'll pay for the coffee. c'est moi qui paie = it's on me. On paie comment ? = how are we paying? (paye/payes spellings also exist; paie is standard.)",
    },
    {
        "infinitive": "boire", "english": "to drink", "family": "irregular",
        "rank": 49, "aux": "avoir", "participle": "bu", "je_reduction": True,
        "present": {"je": "bois", "tu": "bois", "il": "boit", "on": "boit",
                    "vous": "buvez", "ils": "boivent"},
        "imparfait_stem": "buv",
        "street_notes": "bois/boit for everyone singular, then the stem jumps: buvez, boivent, j'ai bu. tu bois quoi ? = what are you drinking? — the bar opener. boire un verre = have a drink.",
    },
]


def tier_for_rank(rank):
    if rank <= 30:
        return 4
    if rank <= 40:
        return 5
    return 6


def main():
    with open(VERBS_PATH) as f:
        data = json.load(f)
    existing = {v["infinitive"] for v in data["verbs"]}
    added = 0
    for v in NEW_VERBS:
        if v["infinitive"] in existing:
            print(f"[skip] {v['infinitive']} (already present)")
            continue
        entry = dict(v)
        entry["tier"] = tier_for_rank(v["rank"])
        data["verbs"].append(entry)
        added += 1
    data["verbs"].sort(key=lambda v: v["rank"])
    with open(VERBS_PATH, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"added {added}; verbs.json now has {len(data['verbs'])} verbs")


if __name__ == "__main__":
    main()
