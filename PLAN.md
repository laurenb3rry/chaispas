# PLAN.md — French Fluency App ("Chais Pas" working title)

A personal iOS app for reaching conversational French fluency as fast as possible, built on Michel Thomas-style audio construction pedagogy plus a first-class "street French" register layer. Designed for one primary user (a false beginner with a trained ear) but architected to assess and adapt to any user.

---

## 1. Product thesis

Fluency decomposes into three separately trained skills:

1. **Sentence construction** — building French in real time, not translating. Trained via Michel Thomas-style audio drilling: English prompt → user speaks French aloud → native reveal → grade. No memorization, no writing, cognate leverage, strictly scaffolded complexity.
2. **Sounding like a local** — spoken French register: ne-drop, *on* for *nous*, tu-contraction, fillers, chunks, connected-speech reductions. Taught as first-class content, paired to every formal construction.
3. **Comprehension of real speech** — fast colloquial audio, trained via adaptive listening and shadowing.

Differentiator: an MT-style construction engine + a systematic street-register layer. No mainstream app does both.

## 2. Pedagogy spec

### 2.1 Concept graph

The atomic unit is a **concept node** in a DAG. Node types:

- `construction` — sentence-building pattern (e.g., *vouloir + infinitive*, negation, futur proche)
- `chunk` — fixed expression learned whole, never analyzed (*ça marche*, *du coup*, *j'en peux plus*)
- `vocab_cluster` — 8–12 thematic words, introduced only in service of constructions
- `register` — phonology/register rule (ne-drop, *on*=*nous*, liaison, *t'as/chais pas* reductions)

Each node carries:
- `id`, `type`, `tier`, `prereq_ids` (DAG edges)
- `title`, `explanation` (≤15 seconds of spoken framing, MT-style, English)
- `canonical_examples` (formal + street form for each)
- `street_mapping` — how the formal form is actually said (text + fast/slow audio)
- `difficulty_tier` (0–3 for v1)

**Hard constraint (the core rule of the entire system):** any drill sentence may only use concepts already introduced to this user. This constraint is enforced by the content pipeline validator and by the session scheduler.

### 2.2 Mastery model

- Each concept holds two independent scores in [0,1]: `production_mastery`, `comprehension_mastery`.
- Each drill response emits evidence: `{concept_ids, axis, correct, latency, timestamp}` and updates the scores of every concept the sentence used (exponential moving average, latency-weighted; slow-but-correct counts less than fast-and-correct).
- Individual **sentences** (not words) are the SRS unit, scheduled with **FSRS**. Concept mastery is derived from performance on sentences containing the concept.
- A concept unlocks when all prerequisites exceed a production threshold (default 0.6). Unlocking is per-axis-aware: comprehension can run ahead of production.
- Placement seeds the priors; every subsequent drill re-estimates them. Assessment is continuous, not a one-time quiz.

### 2.3 Session anatomy (daily, 10–20 min, hands-free capable)

1. **Warm recall** — 2–3 due SRS items, spoken aloud. No new material.
2. **Concept intro** — new node, MT-style framing, ≤15s, cognate leverage where possible.
3. **Construction ladder** — 8–15 English prompts building from 2-word combos to full sentences, only using introduced concepts. Prompt → pause (user speaks) → native reveal → auto-grade via speech recognition (self-grade fallback button). Difficulty auto-adjusts to hold ~70% success.
4. **Street mirror** — today's constructions replayed in casual register: fast audio → slow audio → user shadows twice → pronunciation score.
5. **Spontaneous close** — 2–3 prompts combining today's concept with older ones in novel combinations.

Entire session must work screen-off (audio + speech only). Screen adds affordances but is optional.

## 3. Placement assessment (~8 min, 3 modules)

1. **Comprehension staircase** — audio clips adaptively increasing in speed and register (slow formal → fast street). Tap-the-meaning (4 options). Two consecutive misses ends the staircase. Seeds comprehension priors per tier.
2. **Elicited production** — English prompts sampled across tiers, spoken aloud, graded by speech recognition. Seeds production priors per tier.
3. **Vocab yes/no** — LexTALE-format: real words + plausible pseudo-words (*maisonner*, *bravendre*). Corrects for guessing. Seeds vocab breadth.

Output: prior mastery per (tier × axis). The scheduler fast-forwards comprehension checks the user would ace but still walks production up from the earliest unmastered rung, with reduced rep requirements where latent knowledge shows.

## 4. Curriculum spine — v1, 25 nodes, 4 tiers

Register/street content is embedded per-node via `street_mapping`; nodes marked `register` teach the rule itself.

### Tier 0 — Bootstrap
| # | id | type | title | prereqs |
|---|----|------|-------|---------|
| 1 | `cognate_bridges` | vocab_cluster | -tion / -able / -ible / -aire cognates (~2k instant words) | — |
| 2 | `cest` | construction | *c'est* + adj/noun (*c'est possible*) | 1 |
| 3 | `negation_pas` | construction+register | Negation: spoken norm is ne-drop (*c'est pas grave*); *ne...pas* taught as written form | 2 |
| 4 | `je_veux` | construction | *je veux* + noun / + infinitive | 2 |
| 5 | `chunks_greetings` | chunk | *ça va, coucou, ça marche, ça roule, à toute* | — |

### Tier 1 — Verb spine
| # | id | type | title | prereqs |
|---|----|------|-------|---------|
| 6 | `vouloir_present` | construction | vouloir full present (je/tu/il/on/vous) | 4 |
| 7 | `on_for_nous` | register | *on* replaces *nous* in speech | 6 |
| 8 | `pouvoir_inf` | construction | pouvoir + infinitive | 6 |
| 9 | `devoir_inf` | construction | devoir + infinitive | 8 |
| 10 | `aller_places` | construction | aller + à/en/au + places | 6 |
| 11 | `futur_proche` | construction | aller + infinitive (near future) | 10 |
| 12 | `questions_intonation` | construction+register | Questions: intonation-first (*tu fais quoi ?*), est-ce que second, inversion recognition-only | 6 |
| 13 | `chunks_fillers` | chunk | *bah, du coup, genre, en fait, bref, quoi* | — |

### Tier 2 — Objects & real speech
| # | id | type | title | prereqs |
|---|----|------|-------|---------|
| 14 | `dobj_pronouns` | construction | le/la/les placement | 6,8 |
| 15 | `iobj_pronouns` | construction | me/te/lui/leur | 14 |
| 16 | `y_en` | construction | *y* and *en* (*j'y vais*, *j'en peux plus*) | 14 |
| 17 | `pc_avoir` | construction | passé composé w/ avoir, high-freq participles | 6 |
| 18 | `pc_etre` | construction | passé composé w/ être (movement verbs) | 17 |
| 19 | `connected_speech` | register | *t'as, t'es, chais pas, y'a*, liaison basics | 3,12 |
| 20 | `chunks_reactions` | chunk | *grave, carrément, c'est chaud, n'importe quoi, ça me saoule* | — |

### Tier 3 — Conversation
| # | id | type | title | prereqs |
|---|----|------|-------|---------|
| 21 | `faire_expressions` | construction | il fait beau, ça fait, faire + inf | 17 |
| 22 | `reflexives` | construction+register | je me... with *j'me* reduction | 19 |
| 23 | `imparfait_vs_pc` | construction | storytelling tense contrast | 18 |
| 24 | `relatives_qui_que` | construction | relative clauses | 14 |
| 25 | `conditional_softeners` | construction | *je voudrais, ça serait*, politeness register | 9 |

Each node needs: explanation script, 6–10 canonical examples (formal + street + English), and 30–60 generated drill sentences respecting the DAG constraint.

## 5. Content pipeline (runs locally on laptop, Python)

One-time batch build; app consumes static content packs.

1. **`graph.json`** — the 25 nodes above, hand-authored (with Claude's help), validated for DAG consistency.
2. **`generate_sentences.py`** — calls Claude API per concept: "Generate N drill sentences using ONLY these concepts: [...]. Output JSON: {english, french_formal, french_street, concept_ids}." Batched; total cost ~$1–3.
3. **`validate.py`** — the constraint checker: parses each generated sentence, verifies vocabulary/constructions against the allowed concept set, rejects violations. Simple lexicon + pattern approach for v1; imperfect is fine, it's a filter not a proof.
4. **`tts_batch.py`** — generates audio: Google Cloud TTS (free tier, 1M chars/mo) for formal/slow audio; ElevenLabs (temporary $5 sub, then pause) for street/fast audio. Output: mp3s named by sentence id + variant (`{id}_formal.mp3`, `{id}_street_fast.mp3`, `{id}_street_slow.mp3`).
5. Output bundle: `content_pack_v1/` = graph.json + sentences.json + audio/. Shipped in the app bundle for v1 (no server).

## 6. Tech stack

- **Swift + SwiftUI, iOS 17+**, Xcode, implemented via Claude Code.
- **SwiftData** — persistence: concept state, sentence FSRS state, drill events, sessions.
- **AVFoundation** — playback + mic recording.
- **Speech framework (SFSpeechRecognizer, fr-FR, on-device)** — auto-grading of spoken responses (transcript match with fuzzy tolerance for reductions).
- **Azure Speech Pronunciation Assessment** (free tier, 5 audio-hrs/mo) — phoneme/prosody scoring for shadowing drills. Phase 2; self-grade until then.
- **No backend for v1.** API keys used only by the local content pipeline, never shipped in the app.

### Cost plan
| Item | Cost |
|---|---|
| Google Cloud TTS | $0 (free tier) |
| ElevenLabs | ~$5 one month per content batch, then paused |
| Claude API (generation) | ~$1–3 one-time per batch |
| Azure pronunciation | $0 (free tier) |
| Apple Developer | $0 to start (7-day re-sign) → $99/yr when annoying |

## 7. Data model (SwiftData)

- `ConceptNode`: id, type, tier, prereqIds[], title, explanationText, examples[], streetMapping, introduced: Bool
- `Sentence`: id, conceptIds[], english, frenchFormal, frenchStreet, audioRefs, fsrsState (stability, difficulty, due)
- `DrillEvent`: id, sentenceId, axis (production|comprehension|shadow), correct, latencyMs, pronunciationScore?, timestamp
- `MasteryScore`: conceptId, axis, score, updatedAt
- `SessionLog`: id, date, durationSec, itemsCompleted, newConceptId?

FSRS implementation: port the standard FSRS-4.5 scheduler in Swift (small, well-documented algorithm; no dependency needed).

## 8. Design system — "instrument, not game"

Reference register: Benji Taylor (Vercel, Retro, Family) — restrained, type-driven, native-feeling. No gamification confetti, no mascots, no streak-shame.

- **Palette:** near-monochrome. Background `#0E0E10` (dark-first), surface `#1A1A1D`, primary text `#F4F4F5`, secondary `#8E8E93`. One quiet accent: warm off-white `#E8E3D8` for active states; a single semantic green/red used only for grade feedback, desaturated.
- **Type:** SF Pro with optical sizing; large-title moments use SF Pro Display tight-tracked. French text rendered slightly larger than English prompts — the French is the star.
- **Depth:** soft shadows and material blur, no card borders (consistent with existing preference).
- **Motion:** SwiftUI spring animations throughout (`.spring(response: 0.35, dampingFraction: 0.8)` as baseline); the session player's state transitions (prompt → listening → reveal → grade) are the flagship choreography. Waveform/breathing indicator while mic is live.
- **Haptics:** light impact on reveal, success/warning notification haptics on grade, soft ticks on shadow-score.
- **Hero screen:** the session player. Screen-optional design — one glance communicates state (what phase, what to do). Big center stage for the current prompt/reveal, minimal chrome, progress as a thin hairline not a gamified bar.
- Secondary screens: Today (single CTA into session + due count), Graph (concept map, mastery-tinted), Library (chunks browser with audio), Settings.

## 9. Build phases (Claude Code sequence)

1. **Scaffold** — Xcode project, SwiftData models, design tokens (colors/type/spacing/haptics as a DesignSystem module).
2. **Content pipeline** — Python scripts (graph.json authoring, generation, validation, TTS batch). Produce `content_pack_v1`.
3. **Content loading + FSRS** — pack import, scheduler, mastery model.
4. **Session player** — the hero. Audio loop, phase choreography, self-grade buttons. (Speech recognition stubbed with `BACKFILL` markers.)
5. **Speech grading** — SFSpeechRecognizer integration, fuzzy matching tolerant of street reductions.
6. **Street mirror + shadowing** — fast/slow playback, record-and-compare; Azure scoring behind a `BACKFILL` flag.
7. **Placement assessment** — three modules, prior seeding.
8. **Polish** — motion tuning, haptics, Graph and Library screens, empty states.

Phases 1–4 produce a usable daily-practice app. Ship-to-phone at end of phase 4.

## 10. Deferred (explicitly not v1)

- Backend / accounts / multi-user sync
- Freeform LLM conversation practice mode (great phase-2 feature; needs live API + guardrails)
- Azure pronunciation scoring (phase 2 within build, behind flag)
- Additional tiers beyond the 25-node spine
- App Store distribution
