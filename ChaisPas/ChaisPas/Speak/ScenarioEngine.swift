import Foundation
import SwiftData
import SwiftUI

/// Drives one scenario playthrough (PLAN2 §5.2), fully click-based by user
/// preference — no timers: NPC line shows French only while its street-fast
/// audio plays → tap shows the English → tap advances (or shows the branch
/// choices) → user turn shows the English intent as text only (no prompt
/// audio: the conversation's voice stays French) → the user speaks, then
/// taps → French reveal with audio → self-grade → next exchange. The engine
/// owns audio and state; the view renders and forwards taps.
@MainActor
@Observable
final class ScenarioEngine {
    enum Step: Equatable {
        /// NPC line on stage, French only, street-fast audio playing.
        /// Tap → the English translation.
        case npcSpeaking
        /// NPC line with its English shown. Tap → the next turn.
        case npcGlossed
        /// English intent shown, the user is speaking; tap when done → reveal.
        /// At a former branch point, several intents are offered and any one
        /// is a fine answer (`alternateLines`).
        case userListening
        /// French shown and playing; waiting on a self-grade.
        case userRevealed
        /// Grade landed; brief beat before the next line.
        case userGraded(correct: Bool)
        /// End of the path — summary on screen.
        case ended
    }

    // MARK: Observable state

    /// The other side's current line — stays on stage as context through the
    /// user's reply, so the exchange reads as a conversation.
    private(set) var npcLine: ScenarioNode?
    /// The user's current turn, when it's theirs.
    private(set) var userLine: ScenarioNode?
    /// Whether the current NPC line's English has been tapped open. Stays
    /// true through the user's reply so the exchange keeps its context.
    private(set) var npcGlossShown = false
    private(set) var step: Step = .npcSpeaking
    private(set) var progress: Double = 0
    /// Graded user lines this run (the summary's "exchanges").
    private(set) var exchangesCompleted = 0
    private(set) var correctCount = 0
    private(set) var startedAt = Date.now
    /// The running transcript of what the user is saying — a mirror for
    /// self-grading, never a grade.
    private(set) var spokenText: String?
    var speechActive: Bool { transcriber?.availability == .available }
    /// At a former branch point, the other lines that are equally fine to
    /// say (the user picks by speaking; any is accepted). Empty on a normal
    /// turn.
    private(set) var alternateLines: [ScenarioNode] = []

    let scenario: Scenario
    let variantId: String

    // MARK: Internals

    private let context: ModelContext
    private let audio = AudioPlayer()
    /// Live transcription (PLAN2 §7, revised): a mirror only, never a grader.
    /// Nil when toggled off or under test.
    private let transcriber: SpeechTranscriber?
    /// Test hook: skips audio and shrinks every wait so a full playthrough
    /// runs in milliseconds. Never set from app code.
    private let silent: Bool
    private var nodesById: [String: ScenarioNode] = [:]
    private var firstNodeId: String?
    /// Alternates to attach to the next user turn entered (a collapsed
    /// branch); consumed by `enterUserTurn`.
    private var nextAlternates: [ScenarioNode] = []
    private var nodesConsumed = 0
    private var plannedUnits = 1
    private var promptEndedAt = Date.now
    private var latencyMs = 0
    private var stepTask: Task<Void, Never>?
    private var finished = false

    /// The one remaining wait: a short breath after a grade lands before the
    /// next line enters. Everything else is tap-driven.
    private var gradeBeat: Duration { silent ? .milliseconds(10) : .milliseconds(650) }

    init(scenario: Scenario, context: ModelContext,
         variantId: String? = nil, silent: Bool = false) {
        self.scenario = scenario
        self.context = context
        self.silent = silent
        self.transcriber = (silent || !SpeechTranscriber.enabled) ? nil : SpeechTranscriber()
        let variants = (try? scenario.decodedVariants()) ?? []
        let variant = variants.first { $0.variantId == variantId }
            ?? Self.nextVariant(from: variants, lastPlayed: scenario.variantLastPlayed)
        self.variantId = variant?.variantId ?? ""
        if let variant {
            nodesById = Dictionary(variant.nodes.map { ($0.nodeId, $0) },
                                   uniquingKeysWith: { a, _ in a })
            firstNodeId = variant.nodes.first?.nodeId
            plannedUnits = Self.representativePathLength(of: variant)
        }
    }

    // MARK: Variant rotation (least-recently-played, PLAN2 §5.2)

    /// Never-played variants first (in pack order), then the stalest.
    static func nextVariant(
        from variants: [ScenarioVariant], lastPlayed: [String: Date],
        excluding excludedId: String? = nil
    ) -> ScenarioVariant? {
        let candidates = variants.filter { $0.variantId != excludedId }
        let pool = candidates.isEmpty ? variants : candidates
        return pool.min {
            (lastPlayed[$0.variantId] ?? .distantPast)
                < (lastPlayed[$1.variantId] ?? .distantPast)
        }
    }

    /// Path length following `next` (first branch at branch points) — a
    /// representative denominator for the hairline; the real path varies.
    static func representativePathLength(of variant: ScenarioVariant) -> Int {
        let byId = Dictionary(variant.nodes.map { ($0.nodeId, $0) },
                              uniquingKeysWith: { a, _ in a })
        var length = 0
        var visited = Set<String>()
        var nodeId = variant.nodes.first?.nodeId
        while let id = nodeId, let node = byId[id], visited.insert(id).inserted {
            length += 1
            nodeId = node.next ?? node.branches?.first?.next
        }
        return max(length, 1)
    }

    // MARK: Lifecycle

    func start() {
        if !silent { audio.configureSession() }
        Task { await transcriber?.prepare() }
        startedAt = .now
        // Started counts as played — rotation and "last played" reflect
        // opens, not just completions.
        scenario.lastPlayed = startedAt
        scenario.variantLastPlayed[variantId] = startedAt
        try? context.save()
        guard let firstNodeId, let first = nodesById[firstNodeId] else {
            finish()
            return
        }
        enter(first)
    }

    /// Leaves mid-scenario (the X): stops everything, no completion credit.
    func end() {
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
    }

    /// The live transcript from the mic (PLAN2 §7) — a mirror only: it sets
    /// `spokenText` and nothing else. Fed by the transcriber; also the seam
    /// unit tests drive to prove speech never advances the conversation.
    func applyTranscript(_ text: String) {
        guard step == .userListening || step == .userRevealed else { return }
        transition { self.spokenText = text }
    }

    // MARK: Interactions

    /// Stage tap — the pedal that moves the conversation. NPC French →
    /// English gloss → next turn (or branches); user turn: done speaking →
    /// reveal.
    func stageTapped() {
        switch step {
        case .npcSpeaking:
            stepTask?.cancel()
            audio.stop()
            transition {
                self.npcGlossShown = true
                self.step = .npcGlossed
            }
        case .npcGlossed:
            guard let npc = npcLine else { return }
            stepTask?.cancel()
            audio.stop()
            // A former branch collapses into one user turn: say any of the
            // offered lines and it counts. The paths reconverge, so we walk
            // the first and simply offer the rest as alternates.
            if let branches = npc.branches, !branches.isEmpty {
                let userNodes = branches.compactMap { nodesById[$0.next] }
                guard let primary = userNodes.first else {
                    advance(to: npc.next)
                    return
                }
                nextAlternates = Array(userNodes.dropFirst())
                enter(primary)
            } else {
                advance(to: npc.next)
            }
        case .userListening:
            reveal()
        default:
            break
        }
    }

    /// Replays the current NPC line at either speed — free to use any time
    /// the line is still the active moment (nothing auto-advances anymore).
    func replayNPC(slow: Bool) {
        guard let npc = npcLine,
              let ref = npc.audioRefs?[slow ? "street_slow" : "street_fast"],
              step == .npcSpeaking || step == .npcGlossed
        else { return }
        stepTask?.cancel()
        stepTask = Task { await play(ref, from: .v2Speak) }
    }

    /// The done-speaking tap on the user's turn.
    func reveal() {
        guard step == .userListening, let user = userLine else { return }
        stepTask?.cancel()
        // Mic closes and the transcript freezes for the self-grade.
        transcriber?.stop()
        latencyMs = max(Int(Date.now.timeIntervalSince(promptEndedAt) * 1000), 0)
        transition { self.step = .userRevealed }
        if !silent { DSHaptics.reveal() }
        // The reveal models the target register: street, at street speed.
        if let fast = user.audioRefs?["street_fast"] {
            stepTask = Task { await play(fast, from: .v2Speak) }
        }
    }

    /// Replays the user line's street audio after the reveal.
    func replayUser() {
        guard let user = userLine, step == .userRevealed,
              let ref = user.audioRefs?["street_fast"] else { return }
        stepTask?.cancel()
        stepTask = Task { await play(ref, from: .v2Speak) }
    }

    /// Self-grade for the spoken line — the user's call; speech is a mirror,
    /// never a grader.
    func grade(correct: Bool) {
        guard step == .userRevealed, let user = userLine else { return }
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
        transition { self.step = .userGraded(correct: correct) }
        // Cold CoreHaptics can block the main actor for seconds (the same
        // family as the phase-8 CoreAudio stall) — silent runs skip it.
        if !silent {
            if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }
        }

        recordDrill(nodeId: user.nodeId, correct: correct)
        exchangesCompleted += 1
        if correct { correctCount += 1 }

        stepTask = Task {
            try? await Task.sleep(for: gradeBeat)
            guard !Task.isCancelled else { return }
            advance(to: user.next)
        }
    }

    // MARK: Flow

    private func advance(to nextId: String?) {
        guard let nextId, let node = nodesById[nextId] else {
            finish()
            return
        }
        enter(node)
    }

    private func enter(_ node: ScenarioNode) {
        stepTask?.cancel()
        nodesConsumed += 1
        withAnimation(DSMotion.spring) {
            progress = min(Double(nodesConsumed) / Double(plannedUnits), 0.97)
        }
        if node.speaker == "user" {
            enterUserTurn(node)
        } else {
            enterNPCTurn(node)
        }
    }

    /// French only on screen while the audio plays; the English waits for a
    /// tap. Nothing advances until the user does.
    private func enterNPCTurn(_ node: ScenarioNode) {
        transition {
            self.npcLine = node
            self.userLine = nil
            self.npcGlossShown = false
            self.step = .npcSpeaking
        }
        if let fast = node.audioRefs?["street_fast"] {
            stepTask = Task { await play(fast, from: .v2Speak) }
        }
    }

    /// The user's turn: English intent shown as text only (no prompt audio —
    /// the conversation's voice stays French). The user speaks aloud and
    /// taps when done; no speak-pause timer. The mic opens to mirror what
    /// they say, but never advances anything.
    private func enterUserTurn(_ node: ScenarioNode) {
        let alternates = nextAlternates
        nextAlternates = []
        promptEndedAt = .now
        transition {
            self.userLine = node
            self.alternateLines = alternates
            self.step = .userListening
            self.spokenText = nil
        }
        transcriber?.start { [weak self] text in
            self?.applyTranscript(text)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stepTask?.cancel()
        audio.stop()
        transition {
            self.step = .ended
            self.progress = 1
        }
        scenario.completedCount += 1
        try? context.save()
    }

    // MARK: Spine

    /// Every graded line lands in the one spine. The imported scenario-line
    /// Sentence carries the FSRS state; if a store somehow lacks it, the
    /// DrillEvent is still recorded directly — a grade never silently drops.
    private func recordDrill(nodeId: String, correct: Bool) {
        let sentence = try? context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.id == nodeId }
        )).first
        if let sentence {
            try? MasteryModel.recordDrill(
                sentence: sentence,
                axis: .production,
                correct: correct,
                latencyMs: latencyMs,
                context: context
            )
        } else {
            assertionFailure("No Sentence imported for scenario line \(nodeId)")
            context.insert(DrillEvent(
                sentenceId: nodeId, axis: .production,
                correct: correct, latencyMs: latencyMs
            ))
            try? context.save()
        }
    }

    // MARK: Helpers

    private func play(_ fileName: String, from location: AudioPlayer.Location) async {
        guard !silent else { return }
        await audio.play(fileName: fileName, from: location)
    }

    /// All step mutations animate with the DS baseline spring.
    private func transition(_ mutate: @escaping () -> Void) {
        withAnimation(DSMotion.spring, mutate)
    }
}
