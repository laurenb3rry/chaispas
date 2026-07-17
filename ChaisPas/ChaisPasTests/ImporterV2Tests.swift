//
//  ImporterV2Tests.swift
//  ChaisPasTests
//
//  The migration contract for phase 8 (PLAN2 §4): a store carrying real user
//  state from earlier phases — Sentence FSRS fields, DrillEvents,
//  MasteryScores — must come through the v2 import untouched, and the
//  importer must stay idempotent across relaunches.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

struct ImporterV2Tests {
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

    private func allCounts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<ConceptNode>()),
            try context.fetchCount(FetchDescriptor<Sentence>()),
            try context.fetchCount(FetchDescriptor<DrillEvent>()),
            try context.fetchCount(FetchDescriptor<MasteryScore>()),
            try context.fetchCount(FetchDescriptor<Scenario>()),
            try context.fetchCount(FetchDescriptor<ListenEpisode>()),
            try context.fetchCount(FetchDescriptor<Passage>()),
        ]
    }

    @Test func freshStoreImportsBothPacksAndMatchesManifest() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)

        let manifest = try ContentPackV2.loadManifest().content
        let v1SentenceCount = try ContentPack.loadSentences().sentences.count
        // pack v2 sentences = the Learn drills + one per scenario user line
        // (Speak, phase 11) + one per episode question (Listen, phase 12)
        // + one per passage question (Read, phase 13) — every gradeable
        // interaction drills through the spine
        let userLineTotal = try ContentPackV2.loadScenarios().scenarios
            .flatMap(\.variants).flatMap(\.nodes)
            .filter { $0.speaker == "user" }.count
        let episodeQuestionTotal = try ContentPackV2.loadEpisodes().episodes
            .map(\.questions.count).reduce(0, +)
        let passageQuestionTotal = try ContentPackV2.loadPassages().passages
            .map(\.questions.count).reduce(0, +)
        let v2DrillTotal = manifest.learn.conjugation.drills
            + manifest.learn.vocab.drills + manifest.learn.grammar.drills

        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 })) == v1SentenceCount)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 2 }))
            == v2DrillTotal + userLineTotal + episodeQuestionTotal + passageQuestionTotal)
        #expect(try context.fetchCount(FetchDescriptor<ConceptNode>())
                == 25 + manifest.learn.conjugation.nodes
                + manifest.learn.vocab.nodes + manifest.learn.grammar.nodes)
        #expect(try context.fetchCount(FetchDescriptor<Scenario>()) == manifest.speak.scenarios)
        #expect(try context.fetchCount(FetchDescriptor<ListenEpisode>()) == manifest.listen.episodes)
        #expect(try context.fetchCount(FetchDescriptor<Passage>()) == manifest.read.passages)

        // every sentence (both packs) carries English prompt audio
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.englishAudioRef == nil })) == 0)
    }

    @Test func importIsIdempotentAcrossRelaunches() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let first = try allCounts(context)
        ContentPackImporter.importIfNeeded(context: context)
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try allCounts(context) == first)
    }

    /// Simulates the store a phase-3/4 user carries into the v2 upgrade:
    /// concepts + sentences with live FSRS state, drill history, mastery.
    /// The v2 import must add content without touching any of it.
    @Test func existingUserStateSurvivesV2Import() throws {
        let context = ModelContext(try makeContainer())

        // Seed a pre-v2 store (concept/sentence rows exist → v1 import skips)
        let due = Date.now.addingTimeInterval(86_400 * 3)
        let reviewed = Date.now.addingTimeInterval(-86_400)
        let sentence = Sentence(
            id: "cest_001",
            conceptIds: ["cest", "cognate_bridges"],
            targetConceptId: "cest",
            english: "It's possible.",
            frenchFormal: "C'est possible.",
            frenchStreet: "C'est possible.",
            audioRefs: AudioRefs(formal: "cest_001_formal.mp3",
                                 streetSlow: "cest_001_street_slow.mp3",
                                 streetFast: "cest_001_street_fast.mp3"),
            fsrsStability: 4.2,
            fsrsDifficulty: 5.1,
            fsrsDue: due
        )
        sentence.fsrsLastReviewed = reviewed
        context.insert(sentence)
        context.insert(ConceptNode(
            id: "cest", type: .construction, tier: 0, prereqIds: ["cognate_bridges"],
            title: "c'est + adj/noun", explanationText: "", examples: [],
            streetMapping: "", introduced: true
        ))
        context.insert(DrillEvent(sentenceId: "cest_001", axis: .production,
                                  correct: true, latencyMs: 1800))
        context.insert(MasteryScore(conceptId: "cest", axis: .production, score: 0.42))
        try context.save()

        ContentPackImporter.importIfNeeded(context: context)

        // FSRS state untouched
        let migrated = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == "cest_001" })).first)
        #expect(migrated.fsrsStability == 4.2)
        #expect(migrated.fsrsDifficulty == 5.1)
        #expect(migrated.fsrsDue == due)
        #expect(migrated.fsrsLastReviewed == reviewed)
        #expect(migrated.packVersion == 1)
        // ...while the backfill filled in the new column
        #expect(migrated.englishAudioRef == "cest_001_english.mp3")

        // drill history and mastery untouched
        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 1)
        let mastery = try #require(try context.fetch(
            FetchDescriptor<MasteryScore>()).first)
        #expect(mastery.score == 0.42)
        #expect(mastery.conceptId == "cest")

        // concept survived with its user flag; v2 content arrived alongside
        let cest = try #require(try context.fetch(FetchDescriptor<ConceptNode>(
            predicate: #Predicate { $0.id == "cest" })).first)
        #expect(cest.introduced)
        #expect(try context.fetchCount(FetchDescriptor<Scenario>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Passage>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 2 })) > 0)
    }

    /// Phase 10b: pack updates grow Learn content (new verbs/lessons) and
    /// rewrite explanations. A store built from an older pack must receive
    /// the new units by id-upsert — while every piece of user state (FSRS,
    /// drill history, mastery, introduced flags) survives untouched.
    @Test func packGrowthUpsertsWithoutTouchingUserState() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let fullCounts = try allCounts(context)

        // Simulate the pre-10b store: remove one Learn unit and its drills…
        let removedId = try #require(
            ContentPackV2.loadLearn(.conjugation).nodes.last?.id)
        for node in try context.fetch(FetchDescriptor<ConceptNode>(
            predicate: #Predicate { $0.id == removedId })) {
            context.delete(node)
        }
        for drill in try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.targetConceptId == removedId })) {
            context.delete(drill)
        }
        // …and put live user state on a surviving v2 drill + node.
        let survivor = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 2 && $0.targetConceptId != removedId }
        )).first)
        let due = Date.now.addingTimeInterval(86_400 * 2)
        survivor.fsrsStability = 3.3
        survivor.fsrsDifficulty = 6.6
        survivor.fsrsDue = due
        let survivorId = survivor.id
        let touchedNode = try #require(try context.fetch(FetchDescriptor<ConceptNode>(
            predicate: #Predicate { $0.id != removedId })).first(where: {
                $0.type == .conjugation || $0.type == .grammar
            }))
        touchedNode.introduced = true
        let touchedNodeId = touchedNode.id
        try context.save()

        #expect(ContentPackImporter.needsWork(context: context),
                "a store behind the pack must report needing work")
        ContentPackImporter.importIfNeeded(context: context)

        // the removed unit is back, and totals match a fresh import
        #expect(try context.fetchCount(FetchDescriptor<ConceptNode>(
            predicate: #Predicate { $0.id == removedId })) == 1)
        #expect(try allCounts(context) == fullCounts)
        #expect(!ContentPackImporter.needsWork(context: context))

        // user state survived the upsert byte-for-byte
        let after = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == survivorId })).first)
        #expect(after.fsrsStability == 3.3)
        #expect(after.fsrsDifficulty == 6.6)
        #expect(after.fsrsDue == due)
        let nodeAfter = try #require(try context.fetch(FetchDescriptor<ConceptNode>(
            predicate: #Predicate { $0.id == touchedNodeId })).first)
        #expect(nodeAfter.introduced)
        // and the refreshed explanation actually landed on existing nodes
        #expect(!nodeAfter.explanationText.isEmpty)
    }

    @Test func importedPayloadsDecodeFromTheStore() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)

        let scenario = try #require(try context.fetch(
            FetchDescriptor<Scenario>(sortBy: [SortDescriptor(\.id)])).first)
        let variants = try scenario.decodedVariants()
        #expect(variants.count == 3)
        #expect(variants.allSatisfy { !$0.nodes.isEmpty })

        let episode = try #require(try context.fetch(
            FetchDescriptor<ListenEpisode>(sortBy: [SortDescriptor(\.id)])).first)
        #expect(try episode.decodedTranscript().count > 0)
        #expect(try episode.decodedQuestions().count == 3)
        #expect(episode.speakerLabels.count == 2)

        let passage = try #require(try context.fetch(
            FetchDescriptor<Passage>(sortBy: [SortDescriptor(\.id)])).first)
        #expect(try passage.decodedGloss().count > 0)
        #expect((2...3).contains(try passage.decodedQuestions().count))
    }
}
