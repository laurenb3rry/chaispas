//
//  DrillRunTests.swift
//  ChaisPasTests
//
//  Phase 10 acceptance (PLAN2 §5.1, §9): Learn unit drill runs plan from the
//  unit's pack drills, and every graded drill lands in the shared FSRS queue —
//  one spine, four doors.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

struct DrillRunTests {
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

    private func makeUnit(id: String = "conj_test",
                          type: ConceptType = .conjugation) -> ConceptNode {
        ConceptNode(id: id, type: type, tier: 0, prereqIds: [],
                    title: "test unit", explanationText: "", examples: [],
                    streetMapping: "")
    }

    private func makeDrill(_ id: String, target: String, conceptIds: [String],
                           french: String) -> Sentence {
        Sentence(
            id: id, conceptIds: conceptIds, targetConceptId: target,
            english: "x", frenchFormal: french, frenchStreet: french,
            audioRefs: AudioRefs(formal: "\(id)_formal.mp3",
                                 streetSlow: "\(id)_street_slow.mp3",
                                 streetFast: "\(id)_street_fast.mp3"),
            packVersion: 2, englishAudioRef: "\(id)_english.mp3"
        )
    }

    @Test func drillRunPoolIsUnitScopedAndDifficultySorted() throws {
        let context = try makeContext()
        let unit = makeUnit()
        context.insert(unit)
        // inserted hardest-first to prove the sort; an off-unit drill to
        // prove the scope
        context.insert(makeDrill("t_003", target: unit.id,
                                 conceptIds: ["a", "b", "c", unit.id],
                                 french: "un deux trois quatre"))
        context.insert(makeDrill("t_001", target: unit.id,
                                 conceptIds: [unit.id],
                                 french: "un deux"))
        context.insert(makeDrill("t_002", target: unit.id,
                                 conceptIds: ["a", unit.id],
                                 french: "un deux trois"))
        context.insert(makeDrill("other_001", target: "other_unit",
                                 conceptIds: ["other_unit"], french: "un"))
        try context.save()

        let pool = try SessionPlanner.makeDrillRun(unit: unit, context: context)
        #expect(pool.map(\.id) == ["t_001", "t_002", "t_003"])
    }

    @Test func equalDifficultySurfacesEarlierDueFirst() throws {
        let context = try makeContext()
        let unit = makeUnit()
        context.insert(unit)
        let later = makeDrill("t_b", target: unit.id, conceptIds: [unit.id],
                              french: "un deux")
        later.fsrsDue = Date.now.addingTimeInterval(86_400)
        let sooner = makeDrill("t_a", target: unit.id, conceptIds: [unit.id],
                               french: "un deux")
        sooner.fsrsDue = Date.now.addingTimeInterval(-86_400)
        context.insert(later)
        context.insert(sooner)
        try context.save()

        let pool = try SessionPlanner.makeDrillRun(unit: unit, context: context)
        #expect(pool.map(\.id) == ["t_a", "t_b"])
    }

    /// The acceptance criterion: grading a v2 Learn drill schedules it in the
    /// same FSRS queue the rest of the app reads (the due-review predicate on
    /// Home and the Learn index has no pack filter).
    @Test func gradedV2DrillEntersSharedFSRSQueue() throws {
        let context = try makeContext()
        let unit = makeUnit()
        context.insert(unit)
        let drill = makeDrill("t_001", target: unit.id, conceptIds: [unit.id],
                              french: "un deux")
        context.insert(drill)
        try context.save()

        try MasteryModel.recordDrill(sentence: drill, axis: .production,
                                     correct: true, latencyMs: 1_000,
                                     context: context)

        #expect(drill.fsrsStability > 0)
        let queued = try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.fsrsStability > 0 }
        ))
        #expect(queued == 1)
        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 1)
        // and the unit's mastery moved, since the drill lists it as a concept
        let scores = try MasteryModel.productionScores(context: context)
        #expect((scores[unit.id] ?? 0) > 0)
    }
}
