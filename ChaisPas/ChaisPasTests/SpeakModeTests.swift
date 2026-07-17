//
//  SpeakModeTests.swift
//  ChaisPasTests
//
//  Phase 11 acceptance (PLAN2 §9): a full scenario playthrough with a branch
//  taken, every graded user line landing in the one spine as a production
//  DrillEvent — plus the importer contract for scenario-line sentences and
//  the least-recently-played variant rotation.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

@MainActor
struct SpeakModeTests {
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

    /// Polls until the engine settles in a state the "user" must act on.
    private func waitUntil(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 10
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            try #require(Date.now < deadline, "engine stalled")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Importer

    @Test func importerCreatesASentencePerScenarioUserLine() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)

        let packScenarios = try ContentPackV2.loadScenarios().scenarios
        let userNodes = packScenarios.flatMap(\.variants).flatMap(\.nodes)
            .filter { $0.speaker == "user" }
        let lineSentences = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "scn_") }
        ))
        #expect(lineSentences.count == Set(userNodes.map(\.nodeId)).count)

        // Spot-check the mapping on a known café line.
        let line = try #require(lineSentences.first { $0.id == "scn_cafe_v2_n02" })
        #expect(line.packVersion == 2)
        #expect(line.targetConceptId == "scn_cafe")
        #expect(line.conceptIds.isEmpty)
        #expect(line.audioRefs.streetFast == "scn_cafe_v2_n02_street_fast.mp3")
        #expect(line.englishAudioRef == "scn_cafe_v2_n02_english.mp3")
        #expect(line.frenchFormal.hasPrefix("Bonjour !"))

        // NPC lines never become drillable sentences.
        let npcIds = Set(packScenarios.flatMap(\.variants).flatMap(\.nodes)
            .filter { $0.speaker != "user" }.map(\.nodeId))
        #expect(lineSentences.allSatisfy { !npcIds.contains($0.id) })

        // Idempotent across relaunches, like every other collection.
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "scn_") }
        )) == lineSentences.count)
        #expect(!ContentPackImporter.needsWork(context: context))
    }

    /// A phase-8/9/10 store has Scenario rows but no scenario-line sentences;
    /// the upgrade must add the lines without duplicating the scenarios.
    @Test func lineSentencesBackfillIntoStoresThatPredateSpeak() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let scenarioCount = try context.fetchCount(FetchDescriptor<Scenario>())

        for line in try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "scn_") }
        )) {
            context.delete(line)
        }
        try context.save()

        #expect(ContentPackImporter.needsWork(context: context))
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "scn_") })) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Scenario>()) == scenarioCount)
    }

    // MARK: Variant rotation

    @Test func rotationPicksNeverPlayedThenStalest() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let scenario = try #require(try context.fetch(
            FetchDescriptor<Scenario>(sortBy: [SortDescriptor(\.id)])).first)
        let variants = try scenario.decodedVariants()
        #expect(variants.count == 3)
        let ids = variants.map(\.variantId)

        // Nothing played → first in pack order.
        #expect(ScenarioEngine.nextVariant(from: variants, lastPlayed: [:])?
            .variantId == ids[0])

        // One played → a never-played one wins; the played one is excluded
        // even as `excluding` (both rules point the same way).
        var played = [ids[0]: Date.now]
        #expect(ScenarioEngine.nextVariant(from: variants, lastPlayed: played,
                                           excluding: ids[0])?.variantId == ids[1])

        // All played → the stalest wins…
        played = [
            ids[0]: Date.now.addingTimeInterval(-100),
            ids[1]: Date.now.addingTimeInterval(-3_000),
            ids[2]: Date.now.addingTimeInterval(-200),
        ]
        #expect(ScenarioEngine.nextVariant(from: variants, lastPlayed: played)?
            .variantId == ids[1])
        // …unless it's the one just finished — then the next-stalest.
        #expect(ScenarioEngine.nextVariant(from: variants, lastPlayed: played,
                                           excluding: ids[1])?.variantId == ids[2])
    }

    // MARK: Full playthrough (the phase acceptance, engine-level)

    @Test func fullPlaythroughWithBranchRecordsProductionDrillEvents() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        ContentPackImporter.importIfNeeded(context: context)
        let scenario = try #require(try context.fetch(FetchDescriptor<Scenario>(
            predicate: #Predicate { $0.id == "scn_cafe" })).first)

        let engine = ScenarioEngine(scenario: scenario, context: context, silent: true)
        let variantId = engine.variantId
        engine.start()

        #expect(scenario.lastPlayed != nil)
        #expect(scenario.variantLastPlayed[variantId] != nil)

        // The flow is click-based end to end: every state except the brief
        // post-grade beat waits on a user action, so the driver taps through
        // NPC lines (French → gloss → advance) exactly like a finger would.
        var graded = 0
        var branchesTaken = 0
        var sawGlossGating = false
        var settled: ScenarioEngine.Step?
        for _ in 0..<120 {
            try await waitUntil {
                switch engine.step {
                case .userGraded: false  // the one timed beat
                default: true
                }
            }
            settled = engine.step
            switch engine.step {
            case .npcSpeaking:
                // French first, English gated behind the tap.
                if !engine.npcGlossShown { sawGlossGating = true }
                engine.stageTapped()
                #expect(engine.npcGlossShown, "first tap opens the English")
            case .npcGlossed:
                engine.stageTapped()
            case .userListening:
                engine.reveal()
            case .userRevealed:
                // Miss every fourth line so accuracy math gets both paths.
                engine.grade(correct: graded % 4 != 3)
                graded += 1
            case .branching:
                let branches = engine.branches
                #expect((2...3).contains(branches.count),
                        "branch points offer 2–3 intents")
                engine.choose(try #require(branches.last))
                branchesTaken += 1
            case .ended:
                break
            case .userGraded:
                break
            }
            if settled == .ended { break }
        }
        #expect(sawGlossGating, "NPC lines start French-only")

        #expect(settled == .ended, "playthrough should reach the end")
        #expect(branchesTaken >= 1, "the café scenario has at least one branch point")
        #expect(graded >= 4, "a scenario is a real conversation, not a couple of lines")
        #expect(engine.exchangesCompleted == graded)
        #expect(engine.correctCount == graded - graded / 4)

        // Every graded line landed in the spine as a production event…
        let events = try context.fetch(FetchDescriptor<DrillEvent>())
        #expect(events.count == graded)
        #expect(events.allSatisfy { $0.axis == .production })
        #expect(events.allSatisfy { $0.sentenceId.hasPrefix("scn_cafe") })

        // …and updated the line's FSRS state through recordDrill.
        let firstEventId = try #require(events.first?.sentenceId)
        let reviewed = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == firstEventId })).first)
        #expect(reviewed.fsrsStability > 0)
        #expect(reviewed.fsrsLastReviewed != nil)

        // Completion credit and rotation state.
        #expect(scenario.completedCount == 1)

        // The replay CTA's pick differs from what was just played.
        let next = ScenarioEngine.nextVariant(
            from: try scenario.decodedVariants(),
            lastPlayed: scenario.variantLastPlayed,
            excluding: variantId
        )
        #expect(next != nil && next?.variantId != variantId)
    }

    /// Abandoning mid-scenario (the X) records the grades made so far but no
    /// completion credit.
    @Test func abandonedRunKeepsGradesButNoCompletionCredit() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        ContentPackImporter.importIfNeeded(context: context)
        let scenario = try #require(try context.fetch(FetchDescriptor<Scenario>(
            predicate: #Predicate { $0.id == "scn_cafe" })).first)

        let engine = ScenarioEngine(scenario: scenario, context: context, silent: true)
        engine.start()
        // Tap through the opening NPC line(s) to the first user turn.
        for _ in 0..<10 where engine.step != .userListening {
            engine.stageTapped()
            try await Task.sleep(for: .milliseconds(5))
        }
        try await waitUntil { engine.step == .userListening }
        engine.reveal()
        engine.grade(correct: true)
        engine.end()

        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 1)
        #expect(scenario.completedCount == 0)
        #expect(scenario.lastPlayed != nil, "an abandoned run still counts as played")
    }
}
