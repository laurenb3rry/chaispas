#!/usr/bin/env python3
"""Phase 10b: append the 10 approved new grammar lessons to data/grammar_lessons.json.

Idempotent: skips lessons already present. Run once:
    python data/lessons_10b_additions.py
"""

import json
from pathlib import Path

LESSONS_PATH = Path(__file__).parent / "grammar_lessons.json"

NEW_LESSONS = [
    {
        "id": "gram_venir_de_en_train",
        "title": "Just did / doing right now: venir de & être en train de",
        "tier": 2,
        "prereq_ids": ["futur_proche"],
        "focus": [
            "venir de + infinitive = just did: je viens de manger, il vient de partir — English builds this with tense, French with a frame",
            "être en train de + infinitive = in the middle of: je suis en train de travailler",
            "Only the first verb conjugates — the frame carries the meaning, the infinitive stays frozen",
            "Past versions for storytelling: je venais de partir (had just left), j'étais en train de manger (was in the middle of eating)",
            "With futur proche these frames complete the timeline: just did / doing now / about to",
        ],
        "street_angle": "The frames compress but never drop: j'viens d'arriver, chuis en train de manger, il vient d'partir.",
    },
    {
        "id": "gram_futur_simple",
        "title": "Futur simple: when it beats futur proche",
        "tier": 3,
        "prereq_ids": ["futur_proche"],
        "focus": [
            "Built on the infinitive: -ai, -as, -a, -ez, -ont (je parlerai, tu verras) — -re verbs drop the e first",
            "The irregular stems worth knowing: ser- (être), aur- (avoir), ir- (aller), fer- (faire), pourr-, voudr-, faudr-, viendr-",
            "When it wins: promises and commitments (je t'appellerai), distant or uncertain futures, and after quand for future events (quand tu seras là)",
            "Futur proche stays the spoken default for plans and intentions — the futur simple adds distance or weight",
            "The fixed forms you'll hear daily: on verra, ça ira, tu verras, je te dirai",
        ],
        "street_angle": "Speech leans futur proche hard; the futur simple survives in fixed forms — on verra, ça ira, j'te dirai — and in promises.",
    },
    {
        "id": "gram_subjonctif_survival",
        "title": "Survival subjunctive: il faut que + the forms you'll hear",
        "tier": 3,
        "prereq_ids": ["gram_il_faut"],
        "focus": [
            "The concept in one line: wanted/required/doubted actions take a second verb form after que",
            "il faut que as the workhorse trigger — the spoken replacement for devoir",
            "The 8 audibly-different forms: sois/soit, aies/ait, aille, fasse, puisse, sache, vienne, prenne",
            "Most verbs sound identical to the present — the subjunctive is smaller than it looks",
            "Fixed survival frames: faut que j'y aille, faut qu'on parte, pour que tu puisses",
        ],
        "street_angle": "il drops (faut que j'aille), que elides (faut qu'on...); the whole structure is chunk-like in fast speech.",
    },
    {
        "id": "gram_si_clauses",
        "title": "Si clauses: real ifs and imagined ifs",
        "tier": 3,
        "prereq_ids": ["imparfait_vs_pc", "conditional_softeners"],
        "focus": [
            "Real condition: si + présent, result in présent or futur proche — si t'as le temps, on y va",
            "Hypothetical: si + imparfait, result in conditional — si j'avais le temps, je viendrais",
            "The rule French children chant: never futur or conditionnel directly after si",
            "si on + imparfait alone = a suggestion: si on allait au café ? (how about we...)",
            "si elides only before il: s'il te plaît, s'il pleut — never before elle (si elle)",
        ],
        "street_angle": "si t'as, si y'a, si j'peux — the si clause compresses like any speech, and 'si on allait...' is the everyday way to propose plans.",
    },
    {
        "id": "gram_relatives_dont_ou",
        "title": "Relatives II: dont & où",
        "tier": 3,
        "prereq_ids": ["relatives_qui_que"],
        "focus": [
            "où for places AND times: le café où on va, le jour où je suis arrivé — English says 'when', French says où",
            "dont replaces de + thing: ce dont j'ai besoin, le mec dont je t'ai parlé",
            "The verb picks the pronoun: parler DE quelqu'un → dont; avoir besoin DE → dont — if the verb takes de, the relative is dont",
            "qui/que review in one line: qui = subject, que = object; dont/où extend the same slot",
        ],
        "street_angle": "Relatives don't simplify in speech — le jour où, la meuf dont j'te parlais are everywhere in storytelling.",
    },
    {
        "id": "gram_verb_prepositions",
        "title": "Verb + preposition patterns: essayer de, commencer à",
        "tier": 2,
        "prereq_ids": ["je_veux"],
        "focus": [
            "Three groups: direct infinitive (vouloir, pouvoir, aller, aimer, devoir), à-verbs, de-verbs — learn verb+preposition as one word",
            "The à team: commencer à, apprendre à, réussir à, arriver à (j'arrive pas à dormir)",
            "The de team: essayer de, arrêter de, décider de, oublier de, venir de, éviter de",
            "avant de + infinitive = before doing: avant de partir",
            "When two verbs chain, only the first conjugates; the preposition belongs to the first verb",
        ],
        "street_angle": "Prepositions survive fast speech but elide: j'essaie d'faire, j'arrête de fumer, j'ai oublié d'appeler.",
    },
    {
        "id": "gram_double_pronouns",
        "title": "Two pronouns at once: je te le dis",
        "tier": 3,
        "prereq_ids": ["iobj_pronouns", "y_en"],
        "focus": [
            "The order before the verb: me/te/nous/vous, then le/la/les, then lui/leur, then y, then en",
            "In practice two is the max, and a handful of pairs do all the work: me le, te le, le lui, m'en, y en",
            "Passé composé wraps around them: il me l'a donné, je te l'ai dit",
            "y en a (= il y en a) is the single most common double in French",
        ],
        "street_angle": "Elision chains everything: j'te l'dis, i' m'l'a donné, y'en a plus — the pronouns fuse into one sound block before the verb.",
    },
    {
        "id": "gram_cest_vs_il_est",
        "title": "c'est vs il est",
        "tier": 1,
        "prereq_ids": ["cest"],
        "focus": [
            "c'est + noun, name, or stressed pronoun: c'est mon frère, c'est Marie, c'est moi",
            "il/elle est + adjective alone, for someone or something already named: il est sympa, elle est là",
            "c'est + adjective for general judgments about situations: c'est difficile, c'est bon",
            "Professions flip on the article: elle est médecin, but c'est un médecin",
            "When in doubt, c'est — spoken French leans on it far more than il est",
        ],
        "street_angle": "c'est carries even more load in speech — c'est qui ? c'est quoi ça ? c'est mort — and c'est pas is the everyday negation.",
    },
    {
        "id": "gram_intensifiers",
        "title": "Degree words: trop, grave, carrément",
        "tier": 1,
        "prereq_ids": ["chunks_reactions"],
        "focus": [
            "The neutral ladder: un peu → assez → très → vraiment — all sit before the adjective",
            "trop is the spoken très: c'est trop bien, j'suis trop fatigué — literally 'too', used as 'so'",
            "The street ladder: grave (c'est grave bien), carrément, vachement, hyper/super + adjective",
            "grave and carrément stand alone as full answers: Tu viens ? — Carrément.",
            "Intensity placement never moves: degree word directly before what it scales",
        ],
        "street_angle": "This lesson IS the street register — trop, grave, carrément are how people under 40 actually scale things.",
    },
    {
        "id": "gram_connectors",
        "title": "Discourse glue: du coup, donc, alors, bref",
        "tier": 1,
        "prereq_ids": ["chunks_fillers"],
        "focus": [
            "du coup = 'so / as a result' — the #1 spoken connector, chains any two thoughts",
            "donc and alors both mean 'so': donc concludes, alors moves the story or hesitates (alors...)",
            "parce que = because, reduced to 'passke' in speech; mais, même si, par contre for contrast",
            "Sequencing a story: d'abord, après, ensuite... bref (= long story short) to land it",
            "en fait = 'actually' — the everyday correction word, often opening the sentence",
            "These words buy thinking time — they are what fluency sounds like between sentences",
        ],
        "street_angle": "du coup every four sentences, passke for parce que, bref to end any story — this is the connective tissue of real speech.",
    },
]


def main():
    with open(LESSONS_PATH) as f:
        data = json.load(f)
    existing = {l["id"] for l in data["lessons"]}
    added = 0
    for lesson in NEW_LESSONS:
        if lesson["id"] in existing:
            print(f"[skip] {lesson['id']} (already present)")
            continue
        data["lessons"].append(lesson)
        added += 1
    with open(LESSONS_PATH, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"added {added}; grammar_lessons.json now has {len(data['lessons'])} lessons")


if __name__ == "__main__":
    main()
