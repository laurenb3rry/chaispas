import Foundation
import SwiftData
import SwiftUI

/// Drives the three-module placement assessment (PLAN.md §3, PLAN2 §6):
/// comprehension staircase → elicited production → vocab yes/no → summary,
/// then seeds the priors. All content comes from the shipped packs; the
/// only hand-authored content is the pseudo-word list. The engine owns
/// audio and pacing; the view renders state and forwards taps.
@MainActor
@Observable
final class PlacementEngine {
    enum Module: Int {
        case staircase, production, vocab, summary
    }

    struct StaircaseItem {
        enum Register {
            case formal, streetSlow, streetFast

            var label: String {
                switch self {
                case .formal: "careful and clear"
                case .streetSlow: "street register, slowed"
                case .streetFast: "street register, full speed"
                }
            }
        }

        var tier: Int
        var register: Register
        var audioFile: String
        /// The transcription to match — the register variant the audio speaks.
        var answer: String
    }

    enum StaircaseStep: Equatable {
        /// Audio played; awaiting the typed transcription.
        case listening
        /// Submitted. A match auto-advances; a miss waits for the user —
        /// "close enough" (counts correct) or next (stays a miss).
        case result(matched: Bool)
    }

    struct ProductionItem {
        var sentence: Sentence
        /// v1 tier the prompt samples; nil when it samples a verb.
        var tier: Int?
        /// Conjugation node id when the prompt samples a verb.
        var verbConceptId: String?
    }

    struct VocabItem: Equatable {
        var text: String
        /// Frequency band (0 = most frequent) for real words; nil = pseudo.
        var band: Int?
        var isWord: Bool
    }

    enum ProductionStep: Equatable {
        case prompt, revealed
    }

    /// Plausible-but-fake French for the LexTALE module — hand-authored in
    /// the app by design (PLAN2 phase 14); the packs only carry real French.
    static let pseudoWords = [
        "maisonner", "bravendre", "clavoter", "fournelle", "grispir",
        "vendrelle", "moutarner", "pleuvage", "charnotte", "glissonner",
    ]

    /// (tier, register) ladder the staircase climbs — speed and register
    /// rise together, two rungs per tier.
    static let rungs: [(tier: Int, register: StaircaseItem.Register)] = [
        (0, .formal), (0, .streetSlow),
        (1, .formal), (1, .streetSlow),
        (2, .streetSlow), (2, .streetFast),
        (3, .streetSlow), (3, .streetFast),
    ]

    static let realWordsPerBand = 4
    static let bandCount = 5

    // MARK: Observable state

    private(set) var module: Module = .staircase
    /// Each module opens on a one-line intro; the user taps in when ready —
    /// no surprise audio, no timers (the Speak-interaction standard).
    private(set) var awaitingStart = true

    private(set) var staircaseItems: [StaircaseItem] = []
    private(set) var staircaseIndex = 0
    private(set) var staircaseStep: StaircaseStep = .listening

    private(set) var productionItems: [ProductionItem] = []
    private(set) var productionIndex = 0
    private(set) var productionStep: ProductionStep = .prompt
    /// The running transcript of what the user is saying on a production
    /// prompt — a mirror for self-grading, never a grade.
    private(set) var spokenText: String?
    var speechActive: Bool { transcriber?.availability == .available }

    private(set) var vocabItems: [VocabItem] = []
    private(set) var vocabIndex = 0
    /// The last yes/no tap, tinted right/wrong for a readable beat.
    private(set) var vocabSelection: Bool?

    /// Whether the current vocab tap called it correctly; nil until tapped.
    var vocabWasCorrect: Bool? {
        guard let vocabSelection, let item = currentVocabItem else { return nil }
        return vocabSelection == item.isWord
    }

    private(set) var result: PlacementResult?

    var currentStaircaseItem: StaircaseItem? {
        module == .staircase && !awaitingStart
            && staircaseItems.indices.contains(staircaseIndex)
            ? staircaseItems[staircaseIndex] : nil
    }

    var currentProductionItem: ProductionItem? {
        module == .production && !awaitingStart
            && productionItems.indices.contains(productionIndex)
            ? productionItems[productionIndex] : nil
    }

    var currentVocabItem: VocabItem? {
        module == .vocab && !awaitingStart && vocabItems.indices.contains(vocabIndex)
            ? vocabItems[vocabIndex] : nil
    }

    /// Chrome hairline: thirds per module, answered fraction within each.
    var progress: Double {
        func fraction(_ answered: Int, _ total: Int) -> Double {
            total == 0 ? 0 : Double(answered) / Double(total)
        }
        return switch module {
        case .staircase: fraction(staircaseAnswers.count, staircaseItems.count) / 3
        case .production: (1 + fraction(productionAnswers.count, productionItems.count)) / 3
        case .vocab: (2 + fraction(vocabAnswers.count, vocabItems.count)) / 3
        case .summary: 1
        }
    }

    // MARK: Internals

    private let context: ModelContext
    private let audio = AudioPlayer()
    /// Live transcription for the production module (PLAN2 §6 + §7, revised):
    /// a mirror only, never a grader. Nil when toggled off or under test.
    private let transcriber: SpeechTranscriber?
    /// Test hook: skips audio and shrinks every wait. Never set from app code.
    private let silent: Bool
    private var stepTask: Task<Void, Never>?

    private var staircaseAnswers: [PlacementScoring.StaircaseAnswer] = []
    private var highestRungPassed = -1
    private var consecutiveMisses = 0
    private var productionAnswers: [PlacementScoring.ProductionAnswer] = []
    private var vocabAnswers: [PlacementScoring.VocabAnswer] = []
    private var vocabPackIdsByBand: [Int: [String]] = [:]
    private var seeded = false

    private var answerBeat: Duration { silent ? .milliseconds(10) : .milliseconds(1_000) }
    private var gradeBeat: Duration { silent ? .milliseconds(10) : .milliseconds(500) }
    /// Long enough to read the right/wrong tint before the next word enters.
    private var vocabBeat: Duration { silent ? .milliseconds(10) : .milliseconds(700) }

    init(context: ModelContext, silent: Bool = false,
         seed: UInt64 = .random(in: .min ... .max)) {
        self.context = context
        self.silent = silent
        self.transcriber = (silent || !SpeechTranscriber.enabled) ? nil : SpeechTranscriber()
        let items = PlacementItems.build(context: context, seed: seed)
        staircaseItems = items.staircase
        productionItems = items.production
        vocabItems = items.vocab
        vocabPackIdsByBand = items.vocabPackIdsByBand
    }

    // MARK: Lifecycle

    func start() {
        if !silent { audio.configureSession() }
        Task { await transcriber?.prepare() }
    }

    /// The user taps into the module from its intro line.
    func beginModule() {
        guard awaitingStart, module != .summary else { return }
        transition { self.awaitingStart = false }
        switch module {
        case .staircase:
            guard !staircaseItems.isEmpty else { return enter(.production) }
            playStaircaseAudio()
        case .production:
            if productionItems.isEmpty {
                enter(.vocab)
            } else {
                beginProductionListening()
            }
        case .vocab:
            if vocabItems.isEmpty { finishAssessment() }
        case .summary:
            break
        }
    }

    /// Leaves mid-assessment (the X): stops everything, seeds nothing.
    func abandon() {
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
    }

    /// The live transcript from the mic on a production prompt (PLAN2 §7) — a
    /// mirror only: it sets `spokenText` and nothing else. Fed by the
    /// transcriber; also the seam unit tests drive.
    func applyTranscript(_ text: String) {
        guard module == .production else { return }
        transition { self.spokenText = text }
    }

    private func enter(_ next: Module) {
        stepTask?.cancel()
        audio.stop()
        transition {
            self.module = next
            self.awaitingStart = true
        }
    }

    // MARK: Module 1 — comprehension staircase (type what you hear)

    /// Replay stays available in the result state too — hearing it again is
    /// exactly how you judge "close enough".
    func replayStaircaseAudio() {
        guard currentStaircaseItem != nil else { return }
        playStaircaseAudio()
    }

    private func playStaircaseAudio() {
        guard let item = currentStaircaseItem else { return }
        stepTask?.cancel()
        stepTask = Task { await play(item.audioFile, from: .v1) }
    }

    /// Exact match on the words: case, edge punctuation, typographic
    /// apostrophes, and spacing fold away; accents and the words themselves
    /// don't — "close enough" is the relief valve, not the matcher.
    static func transcriptionMatches(_ typed: String, answer: String) -> Bool {
        normalizeTranscription(typed) == normalizeTranscription(answer)
    }

    static func normalizeTranscription(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "'- ")).inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Submit the typed transcription. A match records right away and
    /// auto-advances; a miss shows the answer and waits — the user resolves
    /// it via `markStaircaseCloseEnough` or `advanceStaircase`.
    func submitStaircase(_ typed: String) {
        guard let item = currentStaircaseItem, staircaseStep == .listening else { return }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stepTask?.cancel()
        audio.stop()
        let matched = Self.transcriptionMatches(trimmed, answer: item.answer)
        transition { self.staircaseStep = .result(matched: matched) }
        gradeHaptic(matched)
        if matched {
            resolveStaircase(correct: true, after: answerBeat)
        }
    }

    /// "Close enough" — the user's own call on a near-miss; counts correct.
    func markStaircaseCloseEnough() {
        guard staircaseStep == .result(matched: false) else { return }
        if !silent { DSHaptics.gradeSuccess() }
        resolveStaircase(correct: true,
                         after: silent ? .milliseconds(10) : .milliseconds(300))
    }

    /// Move on with the miss standing.
    func advanceStaircase() {
        guard staircaseStep == .result(matched: false) else { return }
        resolveStaircase(correct: false,
                         after: silent ? .milliseconds(10) : .milliseconds(150))
    }

    /// Records the rung's outcome; two consecutive standing misses end the
    /// staircase (PLAN.md §3) — a close-enough resets the count.
    private func resolveStaircase(correct: Bool, after beat: Duration) {
        guard let item = currentStaircaseItem else { return }
        staircaseAnswers.append(.init(tier: item.tier, correct: correct))
        if correct {
            highestRungPassed = max(highestRungPassed, staircaseIndex)
            consecutiveMisses = 0
        } else {
            consecutiveMisses += 1
        }

        let ended = consecutiveMisses >= 2 || staircaseIndex + 1 >= staircaseItems.count
        stepTask?.cancel()
        stepTask = Task {
            try? await Task.sleep(for: beat)
            guard !Task.isCancelled else { return }
            if ended {
                self.enter(.production)
            } else {
                self.transition {
                    self.staircaseIndex += 1
                    self.staircaseStep = .listening
                }
                self.playStaircaseAudio()
            }
        }
    }

    // MARK: Module 2 — elicited production (self-graded; the mic mirrors
    // what you say but never grades — PLAN2 §7 revised)

    func revealProduction() {
        guard let item = currentProductionItem, productionStep == .prompt else { return }
        // Mic closes and the transcript freezes for the self-grade.
        transcriber?.stop()
        transition { self.productionStep = .revealed }
        if !silent { DSHaptics.reveal() }
        playProductionAudio(item)
    }

    /// Opens the mic to mirror the user's spoken answer for this prompt.
    private func beginProductionListening() {
        spokenText = nil
        transcriber?.start { [weak self] text in
            self?.applyTranscript(text)
        }
    }

    func replayProductionAudio() {
        guard let item = currentProductionItem, productionStep == .revealed else { return }
        playProductionAudio(item)
    }

    private func playProductionAudio(_ item: ProductionItem) {
        stepTask?.cancel()
        stepTask = Task {
            await self.play(item.sentence.audioRefs.formal,
                            from: item.sentence.packVersion == 2 ? .v2Learn : .v1)
        }
    }

    func gradeProduction(correct: Bool) {
        guard let item = currentProductionItem, productionStep == .revealed else { return }
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
        gradeHaptic(correct)
        productionAnswers.append(.init(
            tier: item.tier, verbConceptId: item.verbConceptId, correct: correct
        ))

        let ended = productionIndex + 1 >= productionItems.count
        stepTask = Task {
            try? await Task.sleep(for: gradeBeat)
            guard !Task.isCancelled else { return }
            if ended {
                self.enter(.vocab)
            } else {
                self.transition {
                    self.productionIndex += 1
                    self.productionStep = .prompt
                }
                self.beginProductionListening()
            }
        }
    }

    // MARK: Module 3 — vocab yes/no

    func answerVocab(saidWord: Bool) {
        guard let item = currentVocabItem, vocabSelection == nil else { return }
        transition { self.vocabSelection = saidWord }
        gradeHaptic(saidWord == item.isWord)
        vocabAnswers.append(.init(band: item.band, isWord: item.isWord, saidWord: saidWord))

        let ended = vocabIndex + 1 >= vocabItems.count
        stepTask = Task {
            try? await Task.sleep(for: vocabBeat)
            guard !Task.isCancelled else { return }
            if ended {
                self.finishAssessment()
            } else {
                self.transition {
                    self.vocabIndex += 1
                    self.vocabSelection = nil
                }
            }
        }
    }

    // MARK: Finish

    /// Scores the run, seeds the priors (once), and lands on the summary.
    private func finishAssessment() {
        stepTask?.cancel()
        audio.stop()
        let result = PlacementScoring.result(
            staircase: staircaseAnswers,
            highestRungPassed: highestRungPassed,
            production: productionAnswers,
            vocab: vocabAnswers,
            vocabPackIdsByBand: vocabPackIdsByBand
        )
        if !seeded {
            seeded = true
            try? PlacementScoring.seed(result, context: context)
            PlacementGate.recordCompletion(result)
        }
        transition {
            self.result = result
            self.module = .summary
            self.awaitingStart = false
        }
    }

    // MARK: Helpers

    private func play(_ fileName: String, from location: AudioPlayer.Location) async {
        guard !silent else { return }
        await audio.play(fileName: fileName, from: location)
    }

    private func gradeHaptic(_ correct: Bool) {
        // Cold CoreHaptics can stall the main actor (the phase-8 family) —
        // silent runs skip it.
        guard !silent else { return }
        if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }
    }

    /// All module/step mutations animate with the DS baseline spring.
    private func transition(_ mutate: @escaping () -> Void) {
        withAnimation(DSMotion.spring, mutate)
    }
}
