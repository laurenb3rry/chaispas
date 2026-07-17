//
//  ListenModeTests.swift
//  ChaisPasTests
//
//  Phase 12 acceptance (PLAN2 §9): the full staged episode flow — cold
//  listen → questions → transcript → slow pass → shadow — with every
//  answered question landing in the one spine as a comprehension DrillEvent,
//  plus the importer contract for question sentences and best-score keeping.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

@MainActor
struct ListenModeTests {
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

    /// Generous timeout: a freshly-booted simulator clone can stall the main
    /// actor for seconds on cold framework inits.
    private func waitUntil(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 30
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            try #require(Date.now < deadline, "engine stalled")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Importer

    @Test func importerCreatesASentencePerEpisodeQuestion() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)

        let packEpisodes = try ContentPackV2.loadEpisodes().episodes
        let questionTotal = packEpisodes.map(\.questions.count).reduce(0, +)
        let questionSentences = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "lst_") }
        ))
        #expect(questionSentences.count == questionTotal)

        // Spot-check the mapping on a known métro question.
        let episode = try #require(packEpisodes.first { $0.id == "lst_b01" })
        let sentence = try #require(questionSentences.first { $0.id == "lst_b01_q1" })
        #expect(sentence.packVersion == 2)
        #expect(sentence.targetConceptId == "lst_b01")
        #expect(sentence.conceptIds.isEmpty)
        #expect(sentence.english == episode.questions[0].question)
        #expect(sentence.frenchFormal
                == episode.questions[0].options[episode.questions[0].answerIndex])

        // Idempotent across relaunches.
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "lst_") }
        )) == questionTotal)
        #expect(!ContentPackImporter.needsWork(context: context))
    }

    /// A phase-8…11 store has ListenEpisode rows but no question sentences;
    /// the upgrade must add them without duplicating episodes.
    @Test func questionSentencesBackfillIntoStoresThatPredateListen() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let episodeCount = try context.fetchCount(FetchDescriptor<ListenEpisode>())

        for sentence in try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "lst_") }
        )) {
            context.delete(sentence)
        }
        try context.save()

        #expect(ContentPackImporter.needsWork(context: context))
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "lst_") })) > 0)
        #expect(try context.fetchCount(FetchDescriptor<ListenEpisode>()) == episodeCount)
    }

    // MARK: Full staged flow (the phase acceptance, engine-level)

    @Test func fullEpisodeFlowRecordsComprehensionEvents() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        ContentPackImporter.importIfNeeded(context: context)
        let episode = try #require(try context.fetch(FetchDescriptor<ListenEpisode>(
            predicate: #Predicate { $0.id == "lst_b01" })).first)

        let engine = ListenEngine(episode: episode, context: context, silent: true)
        engine.start()

        // Stage 1: silent playback completes immediately; nothing readable
        // was ever on offer (the transcript only decodes into stage 3's view).
        try await waitUntil { engine.playback == .finished }
        #expect(engine.stage == .cold)

        // Stage 2: answer the three questions — two right, one wrong.
        engine.toQuestions()
        #expect(engine.questions.count == 3)
        for n in 0..<engine.questions.count {
            try await waitUntil {
                engine.stage == .questions && engine.questionIndex == n
                    && engine.selectedAnswer == nil
            }
            let question = try #require(engine.currentQuestion)
            let wrong = (question.answerIndex + 1) % question.options.count
            engine.answer(n == 1 ? wrong : question.answerIndex)
        }

        // Stage 3: the hub, with completion credit and best score.
        try await waitUntil { engine.stage == .transcript }
        #expect(engine.questionsCompleted)
        #expect(engine.correctCount == 2)
        #expect(episode.completedCount == 1)
        #expect(episode.bestScore == 2)

        let events = try context.fetch(FetchDescriptor<DrillEvent>())
        #expect(events.count == 3)
        #expect(events.allSatisfy { $0.axis == .comprehension })
        #expect(events.allSatisfy { $0.sentenceId.hasPrefix("lst_b01_q") })
        #expect(events.filter(\.correct).count == 2)

        // …and the question sentences carry FSRS state through recordDrill.
        let reviewed = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == "lst_b01_q1" })).first)
        #expect(reviewed.fsrsStability > 0)
        #expect(reviewed.fsrsLastReviewed != nil)

        // Stage 4: slow pass over the transcript, then back.
        engine.toSlowPass()
        try await waitUntil { engine.stage == .slow && engine.playback == .finished }
        engine.backToTranscript()
        #expect(engine.stage == .transcript)

        // Stage 5: shadow two lines with the mirror mechanics, then back.
        engine.toShadow()
        #expect(engine.shadowLines.count == 2)
        try await waitUntil { engine.stage == .transcript }
        let shadowEvents = try context.fetch(FetchDescriptor<DrillEvent>())
            .filter { $0.axis == .shadow }
        #expect(shadowEvents.count == 2)
        #expect(shadowEvents.allSatisfy { event in
            engine.shadowLines.contains { $0.lineId == event.sentenceId }
        })
    }

    /// A better second run raises bestScore; a worse one never lowers it.
    @Test func bestScoreKeepsTheMaximumAcrossRuns() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        ContentPackImporter.importIfNeeded(context: context)
        let episode = try #require(try context.fetch(FetchDescriptor<ListenEpisode>(
            predicate: #Predicate { $0.id == "lst_b01" })).first)

        func run(correctAnswers: Int) async throws {
            let engine = ListenEngine(episode: episode, context: context, silent: true)
            engine.start()
            try await waitUntil { engine.playback == .finished }
            engine.toQuestions()
            for n in 0..<engine.questions.count {
                try await waitUntil {
                    engine.questionIndex == n && engine.selectedAnswer == nil
                }
                let question = try #require(engine.currentQuestion)
                let wrong = (question.answerIndex + 1) % question.options.count
                engine.answer(n < correctAnswers ? question.answerIndex : wrong)
            }
            try await waitUntil { engine.stage == .transcript }
            engine.end()
        }

        try await run(correctAnswers: 3)
        #expect(episode.bestScore == 3)
        try await run(correctAnswers: 1)
        #expect(episode.bestScore == 3, "a worse run must not lower the best")
        #expect(episode.completedCount == 2)
    }

    /// Bailing during the cold listen records nothing and credits nothing.
    @Test func abandonedColdListenLeavesNoTrace() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        ContentPackImporter.importIfNeeded(context: context)
        let episode = try #require(try context.fetch(FetchDescriptor<ListenEpisode>(
            predicate: #Predicate { $0.id == "lst_b01" })).first)

        let engine = ListenEngine(episode: episode, context: context, silent: true)
        engine.start()
        engine.end()

        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 0)
        #expect(episode.completedCount == 0)
        #expect(episode.bestScore == nil)
    }
}
