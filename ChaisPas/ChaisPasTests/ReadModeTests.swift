//
//  ReadModeTests.swift
//  ChaisPasTests
//
//  Phase 13 acceptance (PLAN2 §9): a passage read end to end — glosses
//  resolve (including the pack's multi-word keys), questions grade through
//  the one spine as comprehension DrillEvents, read/lastScore update — plus
//  the importer contract for passage-question sentences.
//

import Foundation
import SwiftData
import Testing
@testable import ChaisPas

@MainActor
struct ReadModeTests {
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

    // MARK: Gloss matching

    @Test func multiWordGlossMatchesFromAnyOfItsWords() {
        let gloss = GlossMatcher.normalizedGloss([
            "ce soir": "tonight", "quoi": "what", "chais pas": "I dunno",
        ])
        let tokens = GlossMatcher.tokenize("On fait quoi ce soir ? Chais pas.")
        // tokens: On fait quoi ce soir ? Chais pas.

        // Tapping either word of a phrase finds the whole phrase…
        let viaFirst = GlossMatcher.match(tokens: tokens, tappedIndex: 3, gloss: gloss)
        let viaSecond = GlossMatcher.match(tokens: tokens, tappedIndex: 4, gloss: gloss)
        #expect(viaFirst == GlossMatcher.Match(range: 3...4, gloss: "tonight"))
        #expect(viaSecond == viaFirst)

        // …case-folds ("Chais" → "chais pas") and strips edge punctuation
        // ("pas." → "pas").
        let folded = GlossMatcher.match(tokens: tokens, tappedIndex: 6, gloss: gloss)
        #expect(folded == GlossMatcher.Match(range: 6...7, gloss: "I dunno"))

        // Single words still match; unglossed words and bare punctuation
        // return nothing.
        #expect(GlossMatcher.match(tokens: tokens, tappedIndex: 2, gloss: gloss)?
            .gloss == "what")
        #expect(GlossMatcher.match(tokens: tokens, tappedIndex: 0, gloss: gloss) == nil)
        #expect(GlossMatcher.match(tokens: tokens, tappedIndex: 5, gloss: gloss) == nil)
    }

    @Test func phrasesDoNotLeakAcrossPunctuation() {
        // "film ?" ends a sentence; "quoi" opens the next. A hypothetical
        // "film quoi" key must not match across the "?" token.
        let gloss = GlossMatcher.normalizedGloss(["film quoi": "WRONG", "film": "movie"])
        let tokens = GlossMatcher.tokenize("un film ? quoi encore")
        let match = GlossMatcher.match(tokens: tokens, tappedIndex: 1, gloss: gloss)
        #expect(match == GlossMatcher.Match(range: 1...1, gloss: "movie"))
    }

    @Test func apostropheAndHyphenWordsMatchThePackForms() throws {
        // Straight from the shipped pack: internal apostrophes and hyphens
        // are word material; typographic apostrophes fold to typewriter.
        let gloss = GlossMatcher.normalizedGloss([
            "t'as": "you have", "vide-grenier": "garage sale",
        ])
        let tokens = GlossMatcher.tokenize("T’as vu le vide-grenier !")
        #expect(GlossMatcher.match(tokens: tokens, tappedIndex: 0, gloss: gloss)?
            .gloss == "you have")
        #expect(GlossMatcher.match(tokens: tokens, tappedIndex: 3, gloss: gloss)?
            .gloss == "garage sale")
    }

    /// Every shipped gloss key must be findable from a tap on its first
    /// word — the whole pack, not a sample; a pipeline change that breaks
    /// key shape should fail loudly here.
    @Test func everyPackGlossKeyIsReachable() throws {
        for passage in try ContentPackV2.loadPassages().passages {
            let gloss = GlossMatcher.normalizedGloss(passage.gloss)
            for key in gloss.keys {
                let tokens = GlossMatcher.tokenize(key)
                let match = GlossMatcher.match(tokens: tokens, tappedIndex: 0, gloss: gloss)
                #expect(match != nil, "unreachable gloss key '\(key)' in \(passage.id)")
            }
        }
    }

    // MARK: Importer

    @Test func importerCreatesASentencePerPassageQuestion() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)

        let packPassages = try ContentPackV2.loadPassages().passages
        let questionTotal = packPassages.map(\.questions.count).reduce(0, +)
        let questionSentences = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "rd_") }
        ))
        #expect(questionSentences.count == questionTotal)

        let passage = try #require(packPassages.first { $0.id == "rd_event_01" })
        let sentence = try #require(questionSentences.first { $0.id == "rd_event_01_q1" })
        #expect(sentence.packVersion == 2)
        #expect(sentence.targetConceptId == "rd_event_01")
        #expect(sentence.english == passage.questions[0].question)
        #expect(sentence.frenchFormal
                == passage.questions[0].options[passage.questions[0].answerIndex])

        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "rd_") })) == questionTotal)
        #expect(!ContentPackImporter.needsWork(context: context))
    }

    /// A phase-8…12 store has Passage rows but no question sentences; the
    /// upgrade must add them without duplicating passages.
    @Test func questionSentencesBackfillIntoStoresThatPredateRead() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let passageCount = try context.fetchCount(FetchDescriptor<Passage>())

        for sentence in try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "rd_") }
        )) {
            context.delete(sentence)
        }
        try context.save()

        #expect(ContentPackImporter.needsWork(context: context))
        ContentPackImporter.importIfNeeded(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id.starts(with: "rd_") })) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Passage>()) == passageCount)
    }

    // MARK: Question run (the phase acceptance, engine-level)

    @Test func answeringAllQuestionsRecordsEventsAndMarksRead() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let passage = try #require(try context.fetch(FetchDescriptor<Passage>(
            predicate: #Predicate { $0.id == "rd_event_01" })).first)

        let engine = ReadEngine(passage: passage, context: context, silent: true)
        #expect((2...3).contains(engine.questions.count))

        // Answer every question — first one wrong, the rest right.
        for (index, question) in engine.questions.enumerated() {
            let wrong = (question.answerIndex + 1) % question.options.count
            engine.answer(question: index, option: index == 0 ? wrong : question.answerIndex)
        }

        #expect(engine.allAnswered)
        #expect(passage.read)
        #expect(passage.lastScore == engine.questions.count - 1)

        let events = try context.fetch(FetchDescriptor<DrillEvent>())
        #expect(events.count == engine.questions.count)
        #expect(events.allSatisfy { $0.axis == .comprehension })
        #expect(events.allSatisfy { $0.sentenceId.hasPrefix("rd_event_01_q") })
        #expect(events.filter(\.correct).count == engine.questions.count - 1)

        // FSRS state landed on the question sentence through recordDrill.
        let reviewed = try #require(try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == "rd_event_01_q1" })).first)
        #expect(reviewed.fsrsStability > 0)

        // Double-answering a question is a no-op.
        let before = try context.fetchCount(FetchDescriptor<DrillEvent>())
        engine.answer(question: 0, option: 0)
        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == before)
    }

    /// lastScore is the LAST run — a worse re-read overwrites honestly;
    /// `read` stays set.
    @Test func rereadOverwritesLastScore() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let passage = try #require(try context.fetch(FetchDescriptor<Passage>(
            predicate: #Predicate { $0.id == "rd_event_01" })).first)

        func run(allCorrect: Bool) {
            let engine = ReadEngine(passage: passage, context: context, silent: true)
            for (index, question) in engine.questions.enumerated() {
                let wrong = (question.answerIndex + 1) % question.options.count
                engine.answer(question: index, option: allCorrect ? question.answerIndex : wrong)
            }
        }

        run(allCorrect: true)
        let total = (try? passage.decodedQuestions().count) ?? 0
        #expect(passage.lastScore == total)
        run(allCorrect: false)
        #expect(passage.lastScore == 0)
        #expect(passage.read)
    }

    /// Closing mid-read records only what was answered and never marks read.
    @Test func abandonedReadLeavesReadUnset() throws {
        let context = ModelContext(try makeContainer())
        ContentPackImporter.importIfNeeded(context: context)
        let passage = try #require(try context.fetch(FetchDescriptor<Passage>(
            predicate: #Predicate { $0.id == "rd_event_01" })).first)

        let engine = ReadEngine(passage: passage, context: context, silent: true)
        let first = try #require(engine.questions.first)
        engine.answer(question: 0, option: first.answerIndex)

        #expect(try context.fetchCount(FetchDescriptor<DrillEvent>()) == 1)
        #expect(!passage.read)
        #expect(passage.lastScore == nil)
    }
}
