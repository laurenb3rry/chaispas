import Foundation
import SwiftData
import SwiftUI

/// State and grading for one passage read (PLAN2 §5.3). No audio, no
/// timers — the page is fully user-paced; this engine only owns the
/// question run and the spine wiring, so it stays unit-testable without
/// the view.
@MainActor
@Observable
final class ReadEngine {
    let passage: Passage
    let questions: [ComprehensionQuestion]
    /// Selected option per question; nil while unanswered. Questions all
    /// sit on the page at once (end-of-chapter style), each locking on tap.
    private(set) var answers: [Int?]
    private(set) var correctCount = 0

    var allAnswered: Bool { answers.allSatisfy { $0 != nil } }

    private let context: ModelContext
    /// Test hook: skips haptics. Never set from app code.
    private let silent: Bool
    private var lastInteractionAt = Date.now
    private var finished = false

    init(passage: Passage, context: ModelContext, silent: Bool = false) {
        self.passage = passage
        self.context = context
        self.silent = silent
        self.questions = (try? passage.decodedQuestions()) ?? []
        self.answers = Array(repeating: nil, count: questions.count)
    }

    /// Tap-answer; each question grades once, through the one spine.
    func answer(question index: Int, option: Int) {
        guard questions.indices.contains(index), answers[index] == nil else { return }
        let question = questions[index]
        let correct = option == question.answerIndex
        withAnimation(DSMotion.spring) { answers[index] = option }
        if correct { correctCount += 1 }
        if !silent {
            if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }
        }

        recordComprehension(questionNumber: index + 1, correct: correct)

        if allAnswered { finish() }
    }

    /// The read is complete when every question is answered: `read` sticks,
    /// `lastScore` reflects this run (a re-read overwrites it, better or
    /// worse — it's "last", the index shows it honestly).
    private func finish() {
        guard !finished else { return }
        finished = true
        passage.read = true
        passage.lastScore = correctCount
        try? context.save()
    }

    private func recordComprehension(questionNumber: Int, correct: Bool) {
        let latencyMs = max(Int(Date.now.timeIntervalSince(lastInteractionAt) * 1000), 0)
        lastInteractionAt = .now
        let id = "\(passage.id)_q\(questionNumber)"
        let sentence = try? context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == id }
        )).first
        if let sentence {
            try? MasteryModel.recordDrill(
                sentence: sentence,
                axis: .comprehension,
                correct: correct,
                latencyMs: latencyMs,
                context: context
            )
        } else {
            assertionFailure("No Sentence imported for passage question \(id)")
            context.insert(DrillEvent(
                sentenceId: id, axis: .comprehension,
                correct: correct, latencyMs: latencyMs
            ))
            try? context.save()
        }
    }
}
