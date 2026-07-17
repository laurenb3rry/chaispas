//
//  RecommendedPathTests.swift
//  ChaisPasTests
//
//  Phase 14 (PLAN2 §5.5): the daily composer — review priority, the
//  gap-weighted round-robin over the Learn modules, difficulty-appropriate
//  Speak and Listen picks, and today's slot detection.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

@MainActor
struct RecommendedPathTests {
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

    // MARK: Learn pick

    @Test func freshStoreRecommendsAFirstUnitAndEasyPicks() throws {
        let context = try importedContext()
        let recommendation = try RecommendedPath.compose(context: context)

        // No history: no reviews exist, every module clock is 0, so the
        // tiebreak order starts at conjugation, lowest tier first.
        guard case .unit(let unit) = recommendation.learn else {
            Issue.record("fresh store should recommend a new unit, got \(recommendation.learn)")
            return
        }
        #expect(unit.type == .conjugation)
        #expect(unit.tier == 0)

        // Level 0 → the easiest scenario and an A episode, nothing done yet.
        #expect(recommendation.speak?.difficulty == 1)
        #expect(recommendation.listen?.level == "A")
        #expect(recommendation.doneCount == 0)
    }

    @Test func overdueConstructionReviewsTakePriority() throws {
        let context = try importedContext()
        let sentence = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 }
        )).first)
        sentence.fsrsStability = 2
        sentence.fsrsDue = Date.now.addingTimeInterval(-3_600)
        try context.save()

        let recommendation = try RecommendedPath.compose(context: context)
        guard case .review(let dueCount) = recommendation.learn else {
            Issue.record("due v1 sentences should recommend the review session")
            return
        }
        #expect(dueCount == 1)
    }

    @Test func overdueLearnDrillsRecommendTheirUnit() throws {
        let context = try importedContext()
        let drills = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.targetConceptId == "conj_etre" }
        ))
        try #require(drills.count >= 2)
        for drill in drills.prefix(2) {
            drill.fsrsStability = 2
            drill.fsrsDue = Date.now.addingTimeInterval(-3_600)
        }
        try context.save()

        let recommendation = try RecommendedPath.compose(context: context)
        guard case .reviewUnit(let unit, let dueCount) = recommendation.learn else {
            Issue.record("due v2 drills should recommend their unit")
            return
        }
        #expect(unit.id == "conj_etre")
        #expect(dueCount == 2)
    }

    /// The acceptance criterion in miniature: priors move the round-robin.
    /// Touching a module advances its clock, so the pick rotates away from
    /// whatever placement (or drilling) shows is already covered.
    @Test func masteryPriorsSteerTheRoundRobin() throws {
        let context = try importedContext()

        func pick() throws -> ConceptNode? {
            let nodes = try context.fetch(FetchDescriptor<ConceptNode>())
            let production = try MasteryModel.scores(axis: .production, context: context)
            return RecommendedPath.nextUnit(nodes: nodes, production: production)
        }

        func seed(_ type: ConceptType, score: Double) throws {
            for node in try context.fetch(FetchDescriptor<ConceptNode>())
            where node.type == type {
                context.insert(MasteryScore(conceptId: node.id, axis: .production, score: score))
            }
            try context.save()
        }

        #expect(try pick()?.type == .conjugation)

        try seed(.conjugation, score: 0.5)
        #expect(try pick()?.type == .grammar,
                "a touched conjugation module should rotate the pick to grammar")

        try seed(.grammar, score: 0.5)
        #expect(try pick()?.type == .vocabPack,
                "touched conjugation and grammar should rotate the pick to vocab")
    }

    @Test func fullyMasteredModulesDropOutOfTheRotation() throws {
        let context = try importedContext()
        let nodes = try context.fetch(FetchDescriptor<ConceptNode>())

        var production: [String: Double] = [:]
        for node in nodes where node.type == .conjugation { production[node.id] = 0.9 }
        let unit = RecommendedPath.nextUnit(nodes: nodes, production: production)
        #expect(unit?.type == .grammar,
                "a mastered module should never be the pick")
    }

    // MARK: Speak pick

    @Test func speakPicksLeastCompletedAtTheRightDifficulty() throws {
        func scenario(_ id: String, difficulty: Int, completed: Int) -> Scenario {
            let scenario = Scenario(id: id, title: id, icon: "cup.and.saucer",
                                    settingBlurb: "", difficulty: difficulty,
                                    variantsData: Data())
            scenario.completedCount = completed
            return scenario
        }
        let scenarios = [
            scenario("scn_a", difficulty: 1, completed: 1),
            scenario("scn_b", difficulty: 2, completed: 0),
            scenario("scn_c", difficulty: 3, completed: 0),
        ]

        // Beginner → nearest to difficulty 1 among the least-completed.
        #expect(RecommendedPath.speakPick(scenarios: scenarios, level: 0)?.id == "scn_b")
        // Strong production → difficulty 3; completion still trumps fit.
        #expect(RecommendedPath.speakPick(scenarios: scenarios, level: 0.7)?.id == "scn_c")
        #expect(RecommendedPath.targetDifficulty(level: 0.4) == 2)
    }

    // MARK: Listen pick

    @Test func listenLevelTracksComprehensionMastery() {
        #expect(RecommendedPath.listenLevel(comprehension: 0) == "A")
        #expect(RecommendedPath.listenLevel(comprehension: 0.3) == "B")
        #expect(RecommendedPath.listenLevel(comprehension: 0.6) == "C")
        #expect(RecommendedPath.listenLevel(comprehension: 0.8) == "D")
    }

    @Test func listenPicksLeastCompletedAtLevelWithFallback() throws {
        func episode(_ id: String, level: String, completed: Int = 0) -> ListenEpisode {
            let episode = ListenEpisode(
                id: id, title: id, level: level, topic: "", speakerLabels: [],
                durationSec: 60, audioFullFast: "", audioFullSlow: "",
                transcriptData: Data(), questionsData: Data()
            )
            episode.completedCount = completed
            return episode
        }
        let episodes = [
            episode("lst_a1", level: "A", completed: 1),
            episode("lst_a2", level: "A"),
            episode("lst_b1", level: "B"),
        ]

        #expect(RecommendedPath.listenPick(episodes: episodes, level: "A")?.id == "lst_a2")
        #expect(RecommendedPath.listenPick(episodes: episodes, level: "B")?.id == "lst_b1")
        // No episodes at the level → nearest level below, never above.
        #expect(RecommendedPath.listenPick(episodes: episodes, level: "D")?.id == "lst_b1")
    }

    // MARK: Today's slots

    @Test func todaysDrillEventsCoverTheirSlots() throws {
        let context = try importedContext()
        let now = Date.now

        // Yesterday's work covers nothing.
        context.insert(DrillEvent(sentenceId: "cest_001", axis: .production,
                                  correct: true, latencyMs: 900,
                                  timestamp: now.addingTimeInterval(-86_400 * 2)))
        try context.save()
        var recommendation = try RecommendedPath.compose(context: context, now: now)
        #expect(recommendation.doneCount == 0)

        // A learn drill, a scenario line, an episode question — each today,
        // each covering exactly its own slot.
        context.insert(DrillEvent(sentenceId: "conj_etre_001", axis: .production,
                                  correct: true, latencyMs: 900, timestamp: now))
        try context.save()
        recommendation = try RecommendedPath.compose(context: context, now: now)
        #expect(recommendation.learnDone && !recommendation.speakDone
                && !recommendation.listenDone)

        context.insert(DrillEvent(sentenceId: "scn_cafe_v1_n02", axis: .production,
                                  correct: true, latencyMs: 900, timestamp: now))
        context.insert(DrillEvent(sentenceId: "lst_a01_q1", axis: .comprehension,
                                  correct: true, latencyMs: 900, timestamp: now))
        try context.save()
        recommendation = try RecommendedPath.compose(context: context, now: now)
        #expect(recommendation.doneCount == 3)

        // Read events are a bonus, not a slot.
        let readOnly = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: readOnly)
        readOnly.insert(DrillEvent(sentenceId: "rd_event_01_q1", axis: .comprehension,
                                   correct: true, latencyMs: 900, timestamp: now))
        try readOnly.save()
        let bonus = try RecommendedPath.compose(context: readOnly, now: now)
        #expect(bonus.doneCount == 0)
    }
}
