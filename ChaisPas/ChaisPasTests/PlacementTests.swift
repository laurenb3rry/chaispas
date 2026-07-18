//
//  PlacementTests.swift
//  ChaisPasTests
//
//  Phase 14 acceptance (PLAN2 §6, §9): the three placement modules run on
//  pack content, the staircase ends on two consecutive misses, scoring is
//  guess-corrected, priors seed max-merged into MasteryScore — and the
//  recommended path visibly responds to them.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

@MainActor
struct PlacementTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
            SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func importedContext() throws -> ModelContext {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        return context
    }

    /// More generous than ListenModeTests' 30s: under a parallel full-target
    /// run, every suite's pack import queues on the main actor ahead of
    /// these polls.
    private func waitUntil(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 90
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            try #require(Date.now < deadline, "engine stalled")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Item construction (everything from the shipped packs)

    @Test func engineBuildsAllThreeModulesFromThePacks() throws {
        let context = try importedContext()
        let engine = PlacementEngine(context: context, silent: true, seed: 7)

        // Staircase: the full (tier, register) ladder, each rung carrying
        // the transcription its audio actually speaks.
        #expect(engine.staircaseItems.count == PlacementEngine.rungs.count)
        for (item, rung) in zip(engine.staircaseItems, PlacementEngine.rungs) {
            #expect(item.tier == rung.tier)
            #expect(!item.answer.isEmpty)
            #expect(!item.audioFile.isEmpty)
        }

        // Production: two prompts per tier plus three sampled verbs.
        #expect(engine.productionItems.count == 11)
        let tiers = engine.productionItems.compactMap(\.tier)
        #expect(tiers == [0, 0, 1, 1, 2, 2, 3, 3])
        let verbs = engine.productionItems.compactMap(\.verbConceptId)
        #expect(verbs.count == 3)
        #expect(verbs.allSatisfy { $0.hasPrefix("conj_") })
        #expect(Set(verbs).count == 3)

        // Vocab: four real words per frequency band plus the pseudo list.
        let real = engine.vocabItems.filter(\.isWord)
        let pseudo = engine.vocabItems.filter { !$0.isWord }
        #expect(real.count == PlacementEngine.bandCount * PlacementEngine.realWordsPerBand)
        #expect(pseudo.count == PlacementEngine.pseudoWords.count)
        for band in 0..<PlacementEngine.bandCount {
            #expect(real.count(where: { $0.band == band }) == PlacementEngine.realWordsPerBand)
        }
        #expect(pseudo.allSatisfy { PlacementEngine.pseudoWords.contains($0.text) })
        #expect(real.allSatisfy { !$0.text.contains(" ") })

        // Different seeds sample different runs (varied replays).
        let other = PlacementEngine(context: context, silent: true, seed: 8)
        #expect(other.staircaseItems.map(\.answer) != engine.staircaseItems.map(\.answer))
    }

    // MARK: Staircase mechanics (typed transcription)

    /// Submits the rung either correctly (the exact answer) or wrongly
    /// (garbage, left standing via Next), then waits out the advance.
    private func answerRung(_ engine: PlacementEngine, correctly: Bool) async throws {
        let item = try #require(engine.currentStaircaseItem)
        engine.submitStaircase(correctly ? item.answer : "zzz zzz")
        if !correctly {
            #expect(engine.staircaseStep == .result(matched: false))
            engine.advanceStaircase()
        }
        try await waitUntil {
            engine.staircaseStep == .listening || engine.module != .staircase
        }
    }

    @Test func twoConsecutiveMissesEndTheStaircase() async throws {
        let context = try importedContext()
        let engine = PlacementEngine(context: context, silent: true, seed: 7)
        engine.start()
        engine.beginModule()

        // Right, wrong, wrong → the staircase ends after three answers.
        for step in 0..<3 {
            try await answerRung(engine, correctly: step == 0)
        }
        try await waitUntil { engine.module == .production }
        #expect(engine.awaitingStart)
    }

    @Test func nonConsecutiveMissesWalkTheWholeStaircase() async throws {
        let context = try importedContext()
        let engine = PlacementEngine(context: context, silent: true, seed: 9)
        engine.start()
        engine.beginModule()

        var answered = 0
        while engine.module == .staircase, engine.currentStaircaseItem != nil {
            try await answerRung(engine, correctly: !answered.isMultiple(of: 2))
            answered += 1
        }
        #expect(answered == engine.staircaseItems.count,
                "alternating misses never trip the two-in-a-row cutoff")
    }

    /// "Close enough" is the user's call and counts as correct — including
    /// for the two-in-a-row cutoff.
    @Test func closeEnoughCountsCorrectAndResetsTheCutoff() async throws {
        let context = try importedContext()
        let engine = PlacementEngine(context: context, silent: true, seed: 7)
        engine.start()
        engine.beginModule()

        for _ in 0..<3 {
            _ = try #require(engine.currentStaircaseItem)
            engine.submitStaircase("pas exactement ça")
            #expect(engine.staircaseStep == .result(matched: false))
            engine.markStaircaseCloseEnough()
            try await waitUntil {
                engine.staircaseStep == .listening || engine.module != .staircase
            }
        }
        #expect(engine.module == .staircase,
                "three close-enough rungs are three correct rungs — no cutoff")
        #expect(engine.staircaseIndex == 3)
    }

    /// Phase 15 (§7, revised): the production transcript is a mirror only.
    /// It sets `spokenText` but never reveals, grades, or advances the
    /// module — the user still taps to reveal and self-grades.
    @Test func liveTranscriptMirrorsButNeverAdvancesProduction() async throws {
        let context = try importedContext()
        let engine = PlacementEngine(context: context, silent: true, seed: 7)
        engine.start()
        // Skip the staircase (all misses) to reach production.
        engine.beginModule()
        while engine.module == .staircase, engine.currentStaircaseItem != nil {
            try await answerRung(engine, correctly: false)
        }
        try await waitUntil { engine.module == .production }
        engine.beginModule()

        let first = try #require(engine.currentProductionItem)
        engine.applyTranscript(first.sentence.frenchFormal)
        #expect(engine.spokenText == first.sentence.frenchFormal)
        // Still the same prompt, still awaiting the user's reveal.
        #expect(engine.productionIndex == 0)
        #expect(engine.productionStep == .prompt)

        // The user drives: reveal, then self-grade, then it advances.
        engine.revealProduction()
        #expect(engine.productionStep == .revealed)
        #expect(engine.spokenText == first.sentence.frenchFormal)
        engine.gradeProduction(correct: true)
        try await waitUntil {
            engine.productionIndex == 1 || engine.module != .production
        }
        #expect(engine.currentProductionItem != nil || engine.module == .vocab)
    }

    @Test func transcriptionMatchingIsExactOnWordsLenientOnTypography() {
        // Case, edge punctuation, typographic apostrophes, spacing: folded.
        #expect(PlacementEngine.transcriptionMatches(
            "c'est pas grave", answer: "C\u{2019}est pas grave."))
        #expect(PlacementEngine.transcriptionMatches(
            "  Je veux   un café ", answer: "Je veux un café."))
        // The words themselves, including accents: exact. That's what the
        // "close enough" affordance is for.
        #expect(!PlacementEngine.transcriptionMatches(
            "je veux un cafe", answer: "Je veux un café."))
        #expect(!PlacementEngine.transcriptionMatches(
            "c'est grave", answer: "C'est pas grave."))
    }

    // MARK: Scoring (pure)

    @Test func tierPriorsMapCleanPartialAndMissed() {
        let priors = PlacementScoring.tierPriors([
            (tier: 0, correct: true), (tier: 0, correct: true),
            (tier: 1, correct: true), (tier: 1, correct: false),
            (tier: 2, correct: false), (tier: 2, correct: false),
        ])
        #expect(priors[0] == PlacementScoring.cleanPrior)
        #expect(priors[1] == PlacementScoring.partialPrior)
        #expect(priors[2] == PlacementScoring.attemptedPrior)
        #expect(priors[3] == nil, "unattempted tiers carry no prior")
    }

    @Test func vocabScoringIsGuessCorrected() {
        // Says "word" to everything: band hit rate 1.0, false-alarm rate
        // 1.0 → corrected 0, no priors, no estimate.
        let yesToAll = PlacementScoring.result(
            staircase: [], highestRungPassed: -1, production: [],
            vocab: [
                .init(band: 0, isWord: true, saidWord: true),
                .init(band: 0, isWord: true, saidWord: true),
                .init(band: nil, isWord: false, saidWord: true),
                .init(band: nil, isWord: false, saidWord: true),
            ],
            vocabPackIdsByBand: [0: ["vocab_pack_01"]]
        )
        #expect(yesToAll.vocabPackPriors.isEmpty)
        #expect(yesToAll.vocabEstimate == 0)

        // Clean discrimination: full hit rate, no false alarms.
        let clean = PlacementScoring.result(
            staircase: [], highestRungPassed: -1, production: [],
            vocab: [
                .init(band: 0, isWord: true, saidWord: true),
                .init(band: 0, isWord: true, saidWord: true),
                .init(band: nil, isWord: false, saidWord: false),
                .init(band: nil, isWord: false, saidWord: false),
            ],
            vocabPackIdsByBand: [0: ["vocab_pack_01", "vocab_pack_02"]]
        )
        #expect(clean.vocabPackPriors == ["vocab_pack_01": 0.6, "vocab_pack_02": 0.6])
        #expect(clean.vocabEstimate == 200)
    }

    @Test func listenLevelAndReadTierComeFromTheStaircase() {
        #expect(PlacementScoring.listenLevel(highestRungPassed: -1) == "A")
        #expect(PlacementScoring.listenLevel(highestRungPassed: 1) == "A")
        #expect(PlacementScoring.listenLevel(highestRungPassed: 3) == "B")
        #expect(PlacementScoring.listenLevel(highestRungPassed: 5) == "C")
        #expect(PlacementScoring.listenLevel(highestRungPassed: 7) == "D")

        let result = PlacementScoring.result(
            staircase: [
                .init(tier: 0, correct: true),
                .init(tier: 1, correct: true),
                .init(tier: 2, correct: false),
            ],
            highestRungPassed: 3, production: [], vocab: [], vocabPackIdsByBand: [:]
        )
        #expect(result.readTier == 1, "read tier is the highest tier actually understood")
        #expect(result.listenLevel == "B")
    }

    // MARK: Seeding

    @Test func seedingMaxMergesAndCoversEveryPriorFamily() throws {
        let context = try importedContext()
        // Pre-existing evidence: one strong score placement must not lower,
        // one weak score it should raise.
        context.insert(MasteryScore(conceptId: "cest", axis: .production, score: 0.9))
        context.insert(MasteryScore(conceptId: "negation_pas", axis: .production, score: 0.2))
        try context.save()

        let result = PlacementResult(
            comprehensionPriorByTier: [0: 0.75],
            productionPriorByTier: [0: 0.75],
            conjugationPriors: ["conj_etre": 0.65],
            vocabPackPriors: ["vocab_pack_01": 0.6],
            listenLevel: "B",
            readTier: 1,
            vocabEstimate: 400
        )
        try PlacementScoring.seed(result, context: context)

        let production = try MasteryModel.scores(axis: .production, context: context)
        let comprehension = try MasteryModel.scores(axis: .comprehension, context: context)

        #expect(production["cest"] == 0.9, "earned evidence is never lowered")
        #expect(production["negation_pas"] == 0.75)
        #expect(comprehension["cest"] == 0.75)
        // Grammar lessons share the 0–3 tier scale and take tier priors too.
        #expect(production["gram_gender_articles"] == 0.75)
        #expect(production["conj_etre"] == 0.65)
        #expect(comprehension["vocab_pack_01"] == 0.6)
        #expect(production["vocab_pack_01"]
                == 0.6 * PlacementScoring.vocabProductionDiscount)
        // Tier-1 concepts were unattempted — untouched.
        #expect(production["vouloir_present"] == nil)

        // Re-seeding is idempotent.
        try PlacementScoring.seed(result, context: context)
        #expect(try MasteryModel.scores(axis: .production, context: context) == production)
    }

    // MARK: The acceptance run: placement → priors → the composer responds

    @Test func strongPlacementRunMovesTheRecommendedPath() async throws {
        let context = try importedContext()

        let before = try RecommendedPath.compose(context: context)
        #expect(before.speak?.difficulty == 1)
        #expect(before.listen?.level == "A")

        let engine = PlacementEngine(context: context, silent: true, seed: 7)
        engine.start()

        // Staircase: every rung transcribed exactly.
        engine.beginModule()
        while engine.module == .staircase, engine.currentStaircaseItem != nil {
            try await answerRung(engine, correctly: true)
        }
        try await waitUntil { engine.module == .production }

        // Production: everything graded "got it".
        engine.beginModule()
        while engine.module == .production, engine.currentProductionItem != nil {
            engine.revealProduction()
            engine.gradeProduction(correct: true)
            try await waitUntil {
                engine.productionStep == .prompt || engine.module != .production
            }
        }
        try await waitUntil { engine.module == .vocab }

        // Vocab: perfect discrimination.
        engine.beginModule()
        while engine.module == .vocab, let item = engine.currentVocabItem {
            engine.answerVocab(saidWord: item.isWord)
            try await waitUntil {
                engine.vocabSelection == nil || engine.module != .vocab
            }
        }
        try await waitUntil { engine.module == .summary }

        let result = try #require(engine.result)
        #expect(result.listenLevel == "D")
        #expect(result.readTier == 3)
        #expect(result.vocabEstimate == 1_000)

        // The priors landed…
        let production = try MasteryModel.scores(axis: .production, context: context)
        #expect(production["cest"] == PlacementScoring.cleanPrior)
        #expect(result.conjugationPriors.allSatisfy { production[$0.key] == $0.value })

        // …and the composer visibly responds: harder scenario, D episode,
        // and the placement run itself recorded no DrillEvents (priors are
        // seeds, not history — the day's slots stay open).
        let after = try RecommendedPath.compose(context: context)
        #expect(after.speak?.difficulty == 3)
        #expect(after.listen?.level == "D")
        #expect(after.doneCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 0)
    }

    // MARK: First-launch gate

    @Test func gateOffersOncePerInstallAndNeverOverDrillHistory() throws {
        let defaults = UserDefaults.standard
        let hadOffered = defaults.bool(forKey: PlacementGate.offeredKey)
        defer {
            if hadOffered {
                defaults.set(true, forKey: PlacementGate.offeredKey)
            } else {
                defaults.removeObject(forKey: PlacementGate.offeredKey)
            }
        }

        defaults.removeObject(forKey: PlacementGate.offeredKey)
        let fresh = try importedContext()
        #expect(PlacementGate.shouldOffer(context: fresh))

        // A store with drill history is never interrupted.
        fresh.insert(DrillEvent(sentenceId: "cest_001", axis: .production,
                                correct: true, latencyMs: 900))
        try fresh.save()
        #expect(!PlacementGate.shouldOffer(context: fresh))

        // Once offered (taken or skipped), never again.
        let untouched = try importedContext()
        PlacementGate.markOffered()
        #expect(!PlacementGate.shouldOffer(context: untouched))
    }
}
