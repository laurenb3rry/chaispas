//
//  EngineTests.swift
//  ChaisPasTests
//

import Foundation
import Testing
@testable import ChaisPas

struct FSRSTests {
    private func makeSentence() -> Sentence {
        Sentence(
            id: "test_001",
            conceptIds: ["cest"],
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
}
