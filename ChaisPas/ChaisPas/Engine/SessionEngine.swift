import Foundation
import SwiftData
import SwiftUI

/// Drives one session through the section-2.3 choreography:
/// warm recall → concept intro → construction ladder → street mirror →
/// spontaneous close. Owns all timing (speak-pauses, auto-reveal, audio
/// sequencing) so views only render state and forward taps.
@MainActor
@Observable
final class SessionEngine {
    /// What one engine run works through. The full MT session is Construction;
    /// a drill run is the single-phase configuration the Learn players share
    /// (PLAN2 §5.1): the same prompt → pause → reveal → grade choreography,
    /// but just the ladder over one unit's drills, then the summary.
    enum Mode {
        case fullSession
        case drillRun(unit: ConceptNode)
    }

    enum Phase: Equatable {
        case warmRecall, conceptIntro, ladder, streetMirror, spontaneous, summary

        var label: String {
            switch self {
            case .warmRecall: "Warm recall"
            case .conceptIntro: "New today"
            case .ladder: "Build it"
            case .streetMirror: "Street mirror"
            case .spontaneous: "Mix it up"
            case .summary: "Done"
            }
        }
    }

    enum DrillStep: Equatable {
        /// Prompt on screen, the user is speaking; auto-reveals after a pause.
        case listening
        /// Native answer shown and playing; waiting on a self-grade.
        case revealed
        /// Grade landed; brief beat before the next item.
        case graded(correct: Bool)
    }

    enum MirrorStep: Equatable {
        case fast, slow
        case shadow(Int)  // 1-based, of shadowReps

        var label: String {
            switch self {
            case .fast: "listen — full speed"
            case .slow: "listen — slowed down"
            case .shadow(let n): "shadow it — \(n) of \(SessionEngine.shadowReps)"
            }
        }
    }

    // MARK: Tuning

    /// Ladder length within the spec's 8–15 range.
    static let ladderLength = 12
    static let spontaneousCount = 3
    static let mirrorCount = 3
    static let shadowReps = 2
    /// Beat between grading and the next prompt.
    static let gradeBeat: Duration = .milliseconds(650)

    // MARK: Observable state

    private(set) var phase: Phase = .warmRecall
    private(set) var currentSentence: Sentence?
    private(set) var drillStep: DrillStep = .listening
    private(set) var mirrorStep: MirrorStep = .fast
    private(set) var progress: Double = 0
    private(set) var itemsCompleted = 0
    private(set) var gradedCount = 0
    private(set) var correctCount = 0
    /// The running transcript of what the user is saying — a mirror for
    /// self-grading, never a grade. Nil when nothing has been heard.
    private(set) var spokenText: String?
    /// The stage shows "listening" instead of "tap to reveal" when the mic
    /// is live.
    var speechActive: Bool { transcriber?.availability == .available }
    var newConcept: ConceptNode? { plan.newConcept }
    var targetConceptTitle: String { plan.targetConceptTitle }
    var startedAt = Date.now

    // MARK: Internals

    private let context: ModelContext
    private let mode: Mode
    private let audio = AudioPlayer()
    /// Live transcription (PLAN2 §7, revised): a mirror only — it never
    /// grades or advances. Nil when the feature is toggled off, so every
    /// path then behaves exactly as before speech existed.
    private let transcriber: SpeechTranscriber? =
        SpeechTranscriber.enabled ? SpeechTranscriber() : nil
    private var plan = SessionPlan(
        warmRecall: [], newConcept: nil, targetConceptId: "",
        targetConceptTitle: "", ladderPool: [], spontaneousPool: []
    )
    private var usedSentenceIds = Set<String>()
    private var promptShownAt = Date.now
    private var latencyMs = 0
    private var stepTask: Task<Void, Never>?

    // Warm recall / spontaneous queues, consumed front-first.
    private var warmQueue: [Sentence] = []
    private var spontaneousQueue: [Sentence] = []

    // Construction ladder: the rung controller walks plan.ladderPool
    // (sorted easiest → hardest). +1 rung on correct, −2 on a miss:
    // the asymmetry equilibrates where p·1 = (1−p)·2, i.e. ~2/3–70% success.
    private var rung = 0
    private var ladderStreak = 0
    private var ladderDrilled: [Sentence] = []

    // Street mirror queue for this session.
    private var mirrorQueue: [Sentence] = []

    /// Estimated total units for the hairline progress bar; refined as
    /// phases resolve their real lengths.
    private var plannedUnits = 1
    private var logged = false

    init(context: ModelContext, mode: Mode = .fullSession) {
        self.context = context
        self.mode = mode
    }

    // MARK: Lifecycle

    func start() {
        audio.configureSession()
        // First use requests mic + speech permission; any refusal just
        // means no transcript — self-grade is unaffected.
        Task { await transcriber?.prepare() }
        startedAt = .now
        switch mode {
        case .fullSession: startFullSession()
        case .drillRun(let unit): startDrillRun(unit: unit)
        }
    }

    private func startFullSession() {
        plan = (try? SessionPlanner.makePlan(context: context))
            ?? SessionPlan(warmRecall: [], newConcept: nil, targetConceptId: "",
                           targetConceptTitle: "", ladderPool: [], spontaneousPool: [])
        warmQueue = plan.warmRecall
        plannedUnits = max(
            plan.warmRecall.count
                + (plan.newConcept == nil ? 0 : 1)
                + min(Self.ladderLength, plan.ladderPool.count)
                + Self.mirrorCount
                + min(Self.spontaneousCount, plan.spontaneousPool.count),
            1
        )
        if warmQueue.isEmpty {
            enterConceptIntro()
        } else {
            transition { self.phase = .warmRecall }
            startDrill(warmQueue.removeFirst())
        }
    }

    /// Single-phase configuration: ladder over the unit's drills, then done.
    /// Opening the unit counts as introducing the concept — soft-recommend
    /// captions elsewhere key off mastery, never off this flag.
    private func startDrillRun(unit: ConceptNode) {
        if !unit.introduced {
            unit.introduced = true
            try? context.save()
        }
        let pool = (try? SessionPlanner.makeDrillRun(unit: unit, context: context)) ?? []
        plan = SessionPlan(
            warmRecall: [], newConcept: nil, targetConceptId: unit.id,
            targetConceptTitle: unit.title, ladderPool: pool, spontaneousPool: []
        )
        plannedUnits = max(min(Self.ladderLength, pool.count), 1)
        enterLadder()
    }

    /// Ends the session from any phase, logging what was completed.
    func end() {
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
        writeSessionLog()
    }

    /// The live transcript from the mic (PLAN2 §7). Purely a mirror: it sets
    /// `spokenText` and nothing else — never grades, reveals, or advances.
    /// Fed by the transcriber; also the injectable seam unit tests drive.
    func applyTranscript(_ text: String) {
        guard drillStep == .listening || drillStep == .revealed else { return }
        transition { self.spokenText = text }
    }

    // MARK: Drill interactions (production items)

    /// User taps to hear the answer before the speak-pause elapses.
    func reveal() { reveal(auto: false) }

    func replayAudio() {
        guard let sentence = currentSentence, drillStep == .revealed else { return }
        stepTask?.cancel()
        stepTask = Task {
            await audio.play(fileName: sentence.audioRefs.formal,
                             from: Self.frenchAudioLocation(of: sentence))
        }
    }

    /// French drill audio ships in the pack the sentence came from.
    private static func frenchAudioLocation(of sentence: Sentence) -> AudioPlayer.Location {
        sentence.packVersion == 2 ? .v2Learn : .v1
    }

    /// Self-grade for the current item. Speech is only a mirror — the user
    /// always makes the call.
    func grade(correct: Bool) {
        guard drillStep == .revealed, let sentence = currentSentence else { return }
        stepTask?.cancel()
        transcriber?.stop()
        audio.stop()
        transition { self.drillStep = .graded(correct: correct) }
        if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }

        // BACKFILL: latency is prompt-shown → reveal, not speech onset;
        // speech recognition will tighten this signal.
        try? MasteryModel.recordDrill(
            sentence: sentence,
            axis: .production,
            correct: correct,
            latencyMs: latencyMs,
            context: context
        )
        gradedCount += 1
        if correct { correctCount += 1 }
        completeUnit()

        if phase == .ladder {
            ladderDrilled.append(sentence)
            ladderStreak = correct ? ladderStreak + 1 : 0
            if correct {
                rung += ladderStreak >= 3 ? 2 : 1
            } else {
                rung = max(rung - 2, 0)
            }
        }

        stepTask = Task {
            try? await Task.sleep(for: Self.gradeBeat)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    /// User taps "Got it" on the concept intro card.
    func confirmIntro() {
        guard phase == .conceptIntro, let concept = plan.newConcept else { return }
        concept.introduced = true
        try? context.save()
        completeUnit()
        enterLadder()
    }

    /// Skips the rest of the current street-mirror item.
    func skipMirrorItem() {
        guard phase == .streetMirror else { return }
        stepTask?.cancel()
        audio.stop()
        advanceMirror()
    }

    // MARK: Phase machine

    private func advance() {
        switch phase {
        case .warmRecall:
            if warmQueue.isEmpty {
                enterConceptIntro()
            } else {
                startDrill(warmQueue.removeFirst())
            }
        case .conceptIntro:
            enterLadder()
        case .ladder:
            if ladderDrilled.count >= Self.ladderLength || nextLadderSentence() == nil {
                finishLadder()
            } else if let next = nextLadderSentence() {
                startDrill(next)
            }
        case .streetMirror:
            advanceMirror()
        case .spontaneous:
            if spontaneousQueue.isEmpty {
                enterSummary()
            } else {
                startDrill(spontaneousQueue.removeFirst())
            }
        case .summary:
            break
        }
    }

    private func enterConceptIntro() {
        guard plan.newConcept != nil else {
            enterLadder()
            return
        }
        transition {
            self.phase = .conceptIntro
            self.currentSentence = nil
        }
    }

    private func enterLadder() {
        guard let first = nextLadderSentence() else {
            finishLadder()
            return
        }
        transition { self.phase = .ladder }
        startDrill(first)
    }

    /// A drill run is just the ladder; the full session carries on into the
    /// street mirror.
    private func finishLadder() {
        switch mode {
        case .fullSession: enterStreetMirror()
        case .drillRun: enterSummary()
        }
    }

    private func enterStreetMirror() {
        // Mirror today's drilled constructions in casual register; sentences
        // whose street form actually differs carry the register lesson.
        let candidates = ladderDrilled.filter { $0.frenchStreet != $0.frenchFormal }
        mirrorQueue = Array((candidates.isEmpty ? ladderDrilled : candidates)
            .suffix(Self.mirrorCount))
        plannedUnits = max(plannedUnits + mirrorQueue.count - Self.mirrorCount, 1)
        guard !mirrorQueue.isEmpty else {
            enterSpontaneous()
            return
        }
        transition { self.phase = .streetMirror }
        startMirrorItem(mirrorQueue.removeFirst())
    }

    private func enterSpontaneous() {
        spontaneousQueue = Array(
            plan.spontaneousPool
                .filter { !usedSentenceIds.contains($0.id) }
                .prefix(Self.spontaneousCount)
        )
        guard !spontaneousQueue.isEmpty else {
            enterSummary()
            return
        }
        transition { self.phase = .spontaneous }
        startDrill(spontaneousQueue.removeFirst())
    }

    private func enterSummary() {
        stepTask?.cancel()
        audio.stop()
        transition {
            self.phase = .summary
            self.currentSentence = nil
            self.progress = 1
        }
        writeSessionLog()
    }

    // MARK: Production drill (prompt → pause → reveal → grade)

    private func startDrill(_ sentence: Sentence) {
        stepTask?.cancel()
        transcriber?.stop()
        usedSentenceIds.insert(sentence.id)
        promptShownAt = .now
        transition {
            self.currentSentence = sentence
            self.drillStep = .listening
            self.spokenText = nil
        }
        // The speak-pause: long enough to say the sentence aloud, scaled to
        // its length. Auto-reveal keeps the flow hands-free capable.
        let words = sentence.frenchFormal.split(separator: " ").count
        let pause = min(max(1.6 + 0.45 * Double(words), 3.0), 8.0)
        // The English prompt is shown, never spoken — every Learn drill reads
        // silently, exactly like Construction (user preference; the English
        // prompt audio files stay in the pack, just unused).
        stepTask = Task {
            // The mic opens immediately so the transcript reflects the user.
            self.transcriber?.start { [weak self] text in
                self?.applyTranscript(text)
            }
            // Auto-reveal is the hands-free (screen-off) affordance. When the
            // transcript mirror is live the user is watching the screen and
            // taps to reveal when done, so the timer would only cut them off.
            guard !self.speechActive else { return }
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            reveal(auto: true)
        }
    }

    private func reveal(auto: Bool) {
        guard drillStep == .listening, let sentence = currentSentence else { return }
        stepTask?.cancel()
        // Close the mic and freeze the transcript for the self-grade.
        transcriber?.stop()
        latencyMs = Int(Date.now.timeIntervalSince(promptShownAt) * 1000)
        transition { self.drillStep = .revealed }
        DSHaptics.reveal()
        stepTask = Task {
            await audio.play(fileName: sentence.audioRefs.formal,
                             from: Self.frenchAudioLocation(of: sentence))
        }
    }

    /// Nearest unused rung at-or-above the controller's position, falling
    /// back to the hardest unused below it.
    private func nextLadderSentence() -> Sentence? {
        let pool = plan.ladderPool
        guard !pool.isEmpty else { return nil }
        let clamped = min(rung, pool.count - 1)
        if let above = pool[clamped...].first(where: { !usedSentenceIds.contains($0.id) }) {
            return above
        }
        return pool[..<clamped].last(where: { !usedSentenceIds.contains($0.id) })
    }

    // MARK: Street mirror (fast → slow → shadow ×2)

    private func startMirrorItem(_ sentence: Sentence) {
        stepTask?.cancel()
        transition {
            self.currentSentence = sentence
            self.mirrorStep = .fast
        }
        let shadowPause = min(
            max(1.2 + 0.35 * Double(sentence.frenchStreet.split(separator: " ").count), 2.5),
            6.0
        )
        stepTask = Task {
            await audio.play(fileName: sentence.audioRefs.streetFast)
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            transition { self.mirrorStep = .slow }
            await audio.play(fileName: sentence.audioRefs.streetSlow)
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            for rep in 1...Self.shadowReps {
                transition { self.mirrorStep = .shadow(rep) }
                await audio.play(fileName: sentence.audioRefs.streetFast)
                try? await Task.sleep(for: .seconds(shadowPause))
                guard !Task.isCancelled else { return }
                DSHaptics.shadowTick()
            }

            // BACKFILL: Azure pronunciation scoring; until then a completed
            // shadow logs as a rep with no score and no FSRS effect.
            self.context.insert(DrillEvent(
                sentenceId: sentence.id, axis: .shadow, correct: true, latencyMs: 0
            ))
            try? self.context.save()
            self.completeUnit()
            self.advanceMirror()
        }
    }

    private func advanceMirror() {
        if mirrorQueue.isEmpty {
            enterSpontaneous()
        } else {
            startMirrorItem(mirrorQueue.removeFirst())
        }
    }

    // MARK: Helpers

    private func completeUnit() {
        itemsCompleted += 1
        withAnimation(DSMotion.spring) {
            progress = min(Double(itemsCompleted) / Double(plannedUnits), 1)
        }
    }

    private func writeSessionLog() {
        guard !logged else { return }
        logged = true
        context.insert(SessionLog(
            date: startedAt,
            durationSec: Int(Date.now.timeIntervalSince(startedAt)),
            itemsCompleted: itemsCompleted,
            newConceptId: plan.newConcept?.introduced == true ? plan.newConcept?.id : nil
        ))
        try? context.save()
    }

    /// All phase/step mutations animate with the DS baseline spring.
    private func transition(_ mutate: @escaping () -> Void) {
        withAnimation(DSMotion.spring, mutate)
    }
}
