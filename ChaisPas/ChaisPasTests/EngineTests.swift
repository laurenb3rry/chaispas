//
//  EngineTests.swift
//  ChaisPasTests
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

struct FSRSTests {
    private func makeSentence() -> Sentence {
        Sentence(
            id: "test_001",
            conceptIds: ["cest"],
            targetConceptId: "cest",
            english: "It's possible.",
            frenchFormal: "C'est possible.",
            frenchStreet: "C'est possible.",
            audioRefs: AudioRefs(formal: "a.mp3", streetSlow: "b.mp3", streetFast: "c.mp3")
        )
    }

    @Test func firstGoodReviewSchedulesRoughlyThreeDaysOut() {
        let s = makeSentence()
        let now = Date.now
        FSRS.review(s, grade: .good, now: now)
        #expect(s.fsrsStability == FSRS.w[2])
        #expect(s.fsrsDifficulty == FSRS.w[4])
        // at 0.9 retention the interval equals the stability (in days)
        let days = s.fsrsDue.timeIntervalSince(now) / 86_400
        #expect(abs(days - FSRS.w[2]) < 0.01)
        #expect(s.fsrsLastReviewed == now)
    }

    @Test func stabilityGrowsAcrossSuccessfulReviews() {
        let s = makeSentence()
        var now = Date.now
        FSRS.review(s, grade: .good, now: now)
        var previous = s.fsrsStability
        for _ in 0..<5 {
            now = s.fsrsDue
            FSRS.review(s, grade: .good, now: now)
            #expect(s.fsrsStability > previous)
            previous = s.fsrsStability
        }
    }

    @Test func lapseShrinksStabilityAndReschedulesInMinutes() {
        let s = makeSentence()
        let first = Date.now
        FSRS.review(s, grade: .good, now: first)
        let grown = s.fsrsStability
        let later = s.fsrsDue
        FSRS.review(s, grade: .again, now: later)
        #expect(s.fsrsStability < grown)
        #expect(s.fsrsDue.timeIntervalSince(later) == FSRS.relearnInterval)
    }

    @Test func retrievabilityDecaysAndHitsTargetAtInterval() {
        // R(0) = 1, and R at the scheduled interval equals desired retention
        #expect(abs(FSRS.retrievability(elapsedDays: 0, stability: 3) - 1) < 1e-9)
        let interval = FSRS.intervalDays(stability: 3)
        let r = FSRS.retrievability(elapsedDays: interval, stability: 3)
        #expect(abs(r - FSRS.desiredRetention) < 1e-9)
    }

    @Test func difficultyStaysClamped() {
        var d = 10.0
        for _ in 0..<50 { d = FSRS.nextDifficulty(d, grade: .again) }
        #expect(d <= 10)
        for _ in 0..<50 { d = FSRS.nextDifficulty(d, grade: .easy) }
        #expect(d >= 1)
    }
}

struct MasteryModelTests {
    @Test func latencyWeighting() {
        #expect(MasteryModel.evidenceValue(correct: false, latencyMs: 500) == 0)
        #expect(MasteryModel.evidenceValue(correct: true, latencyMs: 1_000) == 1)
        #expect(MasteryModel.evidenceValue(correct: true, latencyMs: 20_000) == MasteryModel.slowCredit)
        let mid = MasteryModel.evidenceValue(correct: true, latencyMs: 5_000)
        #expect(mid > MasteryModel.slowCredit && mid < 1)
    }

    @Test func gradeMapping() {
        #expect(MasteryModel.fsrsGrade(correct: false, latencyMs: 100) == .again)
        #expect(MasteryModel.fsrsGrade(correct: true, latencyMs: 1_500) == .good)
        #expect(MasteryModel.fsrsGrade(correct: true, latencyMs: 9_000) == .hard)
    }

    @Test func unlockRequiresAllPrereqsAboveThreshold() {
        let node = ConceptNode(
            id: "negation_pas", type: .constructionRegister, tier: 0,
            prereqIds: ["cest"], title: "", explanationText: "",
            examples: [], streetMapping: ""
        )
        #expect(!MasteryModel.isUnlocked(node, productionScores: [:]))
        #expect(!MasteryModel.isUnlocked(node, productionScores: ["cest": 0.6]))
        #expect(MasteryModel.isUnlocked(node, productionScores: ["cest": 0.61]))
    }

    @Test func emaConvergesUpward() {
        var score = 0.0
        for _ in 0..<30 {
            score += MasteryModel.learningRate * (1 - score)
        }
        #expect(score > MasteryModel.unlockThreshold)
        #expect(score < 1)
    }

    /// The evidence floor for a *correct* answer must clear the unlock gate.
    /// The EMA converges to the evidence target, so a floor at or below the
    /// gate would strand a perfectly accurate learner below it forever — the
    /// Construction "stuck at 1 introduced" bug. Guards the invariant directly.
    @Test func slowCorrectFloorClearsUnlockGate() {
        #expect(MasteryModel.slowCredit > MasteryModel.unlockThreshold)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
            SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    /// End-to-end progression: a learner who is always correct but always slow
    /// (the realistic Construction case — the recorded latency spans reading
    /// the prompt and speaking the whole answer) must eventually push the
    /// target concept's production mastery past the unlock gate, which flips
    /// the next concept to unlocked. This is the regression for the stuck-
    /// forever bug: under the old floor (slowCredit ≤ unlockThreshold) the loop
    /// asymptotes below the gate and `cest` never unlocks.
    @Test func slowButCorrectRepsEventuallyUnlockNextConcept() throws {
        let context = try makeContext()

        let cognates = ConceptNode(
            id: "cognate_bridges", type: .vocabCluster, tier: 0, prereqIds: [],
            title: "Cognate bridges", explanationText: "", examples: [],
            streetMapping: "", introduced: true
        )
        let cest = ConceptNode(
            id: "cest", type: .construction, tier: 0, prereqIds: ["cognate_bridges"],
            title: "C'est", explanationText: "", examples: [], streetMapping: ""
        )
        context.insert(cognates)
        context.insert(cest)

        let drill = Sentence(
            id: "cog_001", conceptIds: ["cognate_bridges"],
            targetConceptId: "cognate_bridges", english: "the situation",
            frenchFormal: "la situation", frenchStreet: "la situation",
            audioRefs: AudioRefs(formal: "a.mp3", streetSlow: "b.mp3", streetFast: "c.mp3")
        )
        context.insert(drill)
        try context.save()

        // cest is gated on cognate_bridges, which starts at 0 mastery.
        #expect(!(try MasteryModel.unlockedConceptIds(context: context)).contains("cest"))

        // Consistently correct, but always in the slow band (≥ slowLatencyMs).
        for _ in 0..<40 {
            try MasteryModel.recordDrill(
                sentence: drill, axis: .production, correct: true,
                latencyMs: 30_000, context: context
            )
        }

        let production = try MasteryModel.productionScores(context: context)
        #expect((production["cognate_bridges"] ?? 0) > MasteryModel.unlockThreshold)
        #expect((try MasteryModel.unlockedConceptIds(context: context)).contains("cest"))
    }
}
