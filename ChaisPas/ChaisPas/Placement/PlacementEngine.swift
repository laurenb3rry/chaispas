import Foundation
import SwiftData
import SwiftUI

/// Deterministic RNG (SplitMix64) so placement runs are seedable in tests
/// while staying varied across real runs.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

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
        var rng = SeededRNG(seed: seed)
        buildItems(rng: &rng)
    }

    // MARK: Lifecycle

    func start() {
        if !silent { audio.configureSession() }
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
            if productionItems.isEmpty { enter(.vocab) }
        case .vocab:
            if vocabItems.isEmpty { finishAssessment() }
        case .summary:
            break
        }
    }

    /// Leaves mid-assessment (the X): stops everything, seeds nothing.
    func abandon() {
        stepTask?.cancel()
        audio.stop()
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

    // MARK: Module 2 — elicited production (self-graded for now;
    // speech recognition replaces the honor system in phase 15)

    func revealProduction() {
        guard let item = currentProductionItem, productionStep == .prompt else { return }
        transition { self.productionStep = .revealed }
        if !silent { DSHaptics.reveal() }
        playProductionAudio(item)
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

    // MARK: Item sampling (all from the shipped packs)

    private func buildItems(rng: inout SeededRNG) {
        let nodes = (try? context.fetch(FetchDescriptor<ConceptNode>())) ?? []
        let v1Tiers = Dictionary(
            nodes.filter { SessionPlanner.v1Types.contains($0.type) }.map { ($0.id, $0.tier) },
            uniquingKeysWith: { a, _ in a }
        )
        let v1Sentences = (try? context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 }
        ))) ?? []
        let byTier = Dictionary(grouping: v1Sentences) { v1Tiers[$0.targetConceptId] ?? -1 }

        buildStaircase(byTier: byTier, rng: &rng)
        buildProduction(byTier: byTier, nodes: nodes, rng: &rng)
        buildVocab(rng: &rng)
    }

    private func buildStaircase(byTier: [Int: [Sentence]], rng: inout SeededRNG) {
        var usedIds = Set<String>()
        for rung in Self.rungs {
            let pool = (byTier[rung.tier] ?? []).filter { !usedIds.contains($0.id) }
            guard let sentence = pool.randomElement(using: &rng) else { continue }
            usedIds.insert(sentence.id)

            // The transcription target is whatever register the audio
            // actually speaks.
            let (audioFile, answer) = switch rung.register {
            case .formal: (sentence.audioRefs.formal, sentence.frenchFormal)
            case .streetSlow: (sentence.audioRefs.streetSlow, sentence.frenchStreet)
            case .streetFast: (sentence.audioRefs.streetFast, sentence.frenchStreet)
            }
            staircaseItems.append(StaircaseItem(
                tier: rung.tier,
                register: rung.register,
                audioFile: audioFile,
                answer: answer
            ))
        }
    }

    private func buildProduction(
        byTier: [Int: [Sentence]], nodes: [ConceptNode], rng: inout SeededRNG
    ) {
        // Two prompts per v1 tier plus one verb after each of the first
        // three tiers: t0 t0 v · t1 t1 v · t2 t2 v · t3 t3 — 11 items.
        var usedIds = Set<String>()
        func tierItem(_ tier: Int) -> ProductionItem? {
            var pool = (byTier[tier] ?? []).filter { !usedIds.contains($0.id) }
            // Middle-difficulty slice: skip the trivial openers and the
            // hardest combinations — one prompt has to stand for the tier.
            pool.sort {
                $0.frenchFormal.split(separator: " ").count
                    < $1.frenchFormal.split(separator: " ").count
            }
            if pool.count >= 8 {
                pool = Array(pool[(pool.count / 4)..<(pool.count * 3 / 4)])
            }
            guard let sentence = pool.randomElement(using: &rng) else { return nil }
            usedIds.insert(sentence.id)
            return ProductionItem(sentence: sentence, tier: tier, verbConceptId: nil)
        }

        let verbs = nodes.filter { $0.type == .conjugation }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
            .prefix(3)
        var verbItems: [ProductionItem] = verbs.compactMap { verb in
            let verbId = verb.id
            let drills = (try? context.fetch(FetchDescriptor<Sentence>(
                predicate: #Predicate { $0.targetConceptId == verbId }
            ))) ?? []
            return drills.randomElement(using: &rng).map {
                ProductionItem(sentence: $0, tier: nil, verbConceptId: verbId)
            }
        }

        for tier in 0...3 {
            productionItems.append(contentsOf: [tierItem(tier), tierItem(tier)].compactMap { $0 })
            if !verbItems.isEmpty, tier < 3 {
                productionItems.append(verbItems.removeFirst())
            }
        }
    }

    private func buildVocab(rng: inout SeededRNG) {
        // Real words sampled across the frequency ranks: the 40 packs fold
        // into 5 bands of 8, four words each.
        let packs = ((try? ContentPackV2.loadLearn(.vocab))?.nodes ?? [])
            .sorted { $0.id < $1.id }
        var real: [VocabItem] = []
        for band in 0..<Self.bandCount {
            let bandPacks = packs.dropFirst(band * 8).prefix(8)
            guard !bandPacks.isEmpty else { continue }
            vocabPackIdsByBand[band] = bandPacks.map(\.id)
            let lemmas = bandPacks.flatMap { $0.words ?? [] }
                .map(\.lemma)
                .filter { !$0.contains(" ") }  // pseudo-words are single tokens
            real.append(contentsOf: lemmas.shuffled(using: &rng)
                .prefix(Self.realWordsPerBand)
                .map { VocabItem(text: $0, band: band, isWord: true) })
        }
        guard !real.isEmpty else { return }
        let pseudo = Self.pseudoWords.map { VocabItem(text: $0, band: nil, isWord: false) }
        vocabItems = (real + pseudo).shuffled(using: &rng)
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
