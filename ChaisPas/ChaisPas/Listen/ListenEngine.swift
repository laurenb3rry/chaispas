import Foundation
import SwiftData
import SwiftUI

/// Drives one episode through the §5.4 staged flow: cold listen at full
/// speed (audio only) → tap-answer comprehension questions → transcript
/// reveal with per-line replay → optional slow pass over the transcript →
/// optional shadow of two lines (street-mirror mechanics). Stage changes are
/// user-paced taps (the Speak lesson); the only timed waits are the beat
/// after an answer lands and the shadow speak-pauses the mirror mechanics
/// call for. The engine owns audio and state; the view renders and forwards.
@MainActor
@Observable
final class ListenEngine {
    enum Stage: Equatable {
        /// Stage 1: full-speed audio, nothing to read. The point of the mode.
        case cold
        /// Stage 2: the comprehension questions, one at a time.
        case questions
        /// Stage 3 (and the hub): transcript with per-line replay; slow pass
        /// and shadow depart from here and return here.
        case transcript
        /// Stage 4: full-slow audio over the visible transcript.
        case slow
        /// Stage 5: shadow two lines, fast → slow → shadow ×2.
        case shadow
    }

    enum PlaybackState: Equatable {
        case playing, paused, finished
    }

    enum ShadowStep: Equatable {
        case fast, slow
        case shadow(Int)  // 1-based, of SessionEngine.shadowReps

        var label: String {
            switch self {
            case .fast: "listen — full speed"
            case .slow: "listen — slowed down"
            case .shadow(let n): "shadow it — \(n) of \(SessionEngine.shadowReps)"
            }
        }
    }

    // MARK: Observable state

    private(set) var stage: Stage = .cold
    /// Cold/slow full-episode playback state.
    private(set) var playback: PlaybackState = .playing
    /// Fraction of the current full-episode file played (drives the hairline).
    private(set) var playbackProgress: Double = 0
    private(set) var questionIndex = 0
    /// The tapped option for the current question; nil while unanswered.
    private(set) var selectedAnswer: Int?
    private(set) var correctCount = 0
    /// Questions have been answered this run (the hub shows the score).
    private(set) var questionsCompleted = false
    /// Line currently replaying from the transcript (tinted in the list).
    private(set) var playingLineId: String?
    private(set) var shadowLines: [TranscriptLine] = []
    private(set) var shadowIndex = 0
    private(set) var shadowStep: ShadowStep = .fast
    private(set) var startedAt = Date.now

    let episode: ListenEpisode
    let lines: [TranscriptLine]
    let questions: [ComprehensionQuestion]

    /// Chrome hairline: playback through the listens, question progress
    /// through the questions, full afterwards.
    var progress: Double {
        switch stage {
        case .cold, .slow: playbackProgress
        case .questions:
            (Double(questionIndex) + (selectedAnswer == nil ? 0 : 1))
                / Double(max(questions.count, 1))
        case .transcript, .shadow: 1
        }
    }

    var currentQuestion: ComprehensionQuestion? {
        stage == .questions && questions.indices.contains(questionIndex)
            ? questions[questionIndex] : nil
    }

    var currentShadowLine: TranscriptLine? {
        stage == .shadow && shadowLines.indices.contains(shadowIndex)
            ? shadowLines[shadowIndex] : nil
    }

    // MARK: Internals

    private let context: ModelContext
    private let audio = AudioPlayer()
    /// Test hook: skips audio and shrinks every wait. Never set from app code.
    private let silent: Bool
    private var questionShownAt = Date.now
    private var stepTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    /// The breath after an answer lands — long enough to read the tint and
    /// spot the correct option before the next question enters.
    private var answerBeat: Duration { silent ? .milliseconds(10) : .milliseconds(1_200) }

    init(episode: ListenEpisode, context: ModelContext, silent: Bool = false) {
        self.episode = episode
        self.context = context
        self.silent = silent
        self.lines = (try? episode.decodedTranscript()) ?? []
        self.questions = (try? episode.decodedQuestions()) ?? []
    }

    // MARK: Lifecycle

    func start() {
        if !silent { audio.configureSession() }
        startedAt = .now
        startFullListen(slow: false)
    }

    /// Leaves mid-episode (the X): stops everything; no completion credit.
    func end() {
        stepTask?.cancel()
        progressTask?.cancel()
        audio.stop()
    }

    // MARK: Full-episode playback (stages 1 and 4)

    private func startFullListen(slow: Bool) {
        stepTask?.cancel()
        transition {
            self.stage = slow ? .slow : .cold
            self.playback = .playing
            self.playbackProgress = 0
        }
        let file = slow ? episode.audioFullSlow : episode.audioFullFast
        stepTask = Task {
            await play(file, from: .v2Listen)
            guard !Task.isCancelled else { return }
            transition {
                self.playback = .finished
                self.playbackProgress = 1
            }
        }
        startProgressPolling()
    }

    /// Display-only: samples the player position while a full mix runs.
    private func startProgressPolling() {
        progressTask?.cancel()
        guard !silent else { return }
        progressTask = Task {
            while !Task.isCancelled, playback != .finished {
                if playback == .playing {
                    playbackProgress = audio.playbackProgress
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func pausePlayback() {
        guard playback == .playing else { return }
        audio.pause()
        transition { self.playback = .paused }
    }

    func resumePlayback() {
        guard playback == .paused else { return }
        audio.resume()
        transition { self.playback = .playing }
    }

    /// "Listen again" on the finished cold stage.
    func replayCold() {
        guard stage == .cold else { return }
        startFullListen(slow: false)
    }

    // MARK: Questions (stage 2)

    func toQuestions() {
        guard stage == .cold else { return }
        stepTask?.cancel()
        progressTask?.cancel()
        audio.stop()
        questionShownAt = .now
        transition {
            self.stage = .questions
            self.questionIndex = 0
            self.selectedAnswer = nil
            self.correctCount = 0
        }
    }

    /// Tap-answer. The answer is the click; after a readable beat the next
    /// question enters (or the transcript, after the last).
    func answer(_ index: Int) {
        guard stage == .questions, selectedAnswer == nil,
              let question = currentQuestion else { return }
        let correct = index == question.answerIndex
        transition { self.selectedAnswer = index }
        // Cold CoreHaptics can block the main actor for seconds (the same
        // family as the phase-8 CoreAudio stall) — silent runs skip it.
        if !silent {
            if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }
        }
        if correct { correctCount += 1 }

        recordComprehension(questionNumber: questionIndex + 1, correct: correct)

        stepTask = Task {
            try? await Task.sleep(for: answerBeat)
            guard !Task.isCancelled else { return }
            if questionIndex + 1 < questions.count {
                questionShownAt = .now
                transition {
                    self.questionIndex += 1
                    self.selectedAnswer = nil
                }
            } else {
                finishQuestions()
            }
        }
    }

    /// The question run is the episode's completion: credit and best score
    /// land here; the transcript hub and everything after are optional.
    private func finishQuestions() {
        questionsCompleted = true
        episode.completedCount += 1
        episode.bestScore = max(episode.bestScore ?? 0, correctCount)
        try? context.save()
        transition { self.stage = .transcript }
    }

    // MARK: Transcript (stage 3, the hub)

    /// Per-line replay at full speed; tapping the playing line stops it.
    func playLine(_ line: TranscriptLine) {
        guard stage == .transcript else { return }
        stepTask?.cancel()
        if playingLineId == line.lineId {
            audio.stop()
            transition { self.playingLineId = nil }
            return
        }
        transition { self.playingLineId = line.lineId }
        stepTask = Task {
            await play(line.audioRefs.fast, from: .v2Listen)
            guard !Task.isCancelled else { return }
            transition { self.playingLineId = nil }
        }
    }

    /// Stage 4: the slow mix plays under the visible transcript.
    func toSlowPass() {
        guard stage == .transcript else { return }
        transition { self.playingLineId = nil }
        startFullListen(slow: true)
    }

    /// Back from the slow pass (any time — it's optional).
    func backToTranscript() {
        guard stage == .slow || stage == .shadow else { return }
        stepTask?.cancel()
        progressTask?.cancel()
        audio.stop()
        transition {
            self.stage = .transcript
            self.playingLineId = nil
        }
    }

    // MARK: Shadow (stage 5 — street-mirror mechanics)

    /// The two meatiest lines carry the most shadowing value.
    func toShadow() {
        guard stage == .transcript else { return }
        stepTask?.cancel()
        audio.stop()
        shadowLines = Array(
            lines.sorted {
                $0.frenchStreet.split(separator: " ").count
                    > $1.frenchStreet.split(separator: " ").count
            }
            .prefix(2)
        )
        guard !shadowLines.isEmpty else { return }
        transition {
            self.stage = .shadow
            self.shadowIndex = 0
            self.playingLineId = nil
        }
        startShadowItem()
    }

    /// Fast → slow → shadow ×2 with speak-pauses, exactly the street mirror.
    private func startShadowItem() {
        guard let line = currentShadowLine else {
            backToTranscript()
            return
        }
        stepTask?.cancel()
        transition { self.shadowStep = .fast }
        let words = line.frenchStreet.split(separator: " ").count
        let shadowPause = silent ? 0.01 : min(max(1.2 + 0.35 * Double(words), 2.5), 6.0)
        let betweenBeat: Duration = silent ? .milliseconds(10) : .milliseconds(400)
        stepTask = Task {
            await play(line.audioRefs.fast, from: .v2Listen)
            try? await Task.sleep(for: betweenBeat)
            guard !Task.isCancelled else { return }

            transition { self.shadowStep = .slow }
            await play(line.audioRefs.slow, from: .v2Listen)
            try? await Task.sleep(for: betweenBeat)
            guard !Task.isCancelled else { return }

            for rep in 1...SessionEngine.shadowReps {
                transition { self.shadowStep = .shadow(rep) }
                await play(line.audioRefs.fast, from: .v2Listen)
                try? await Task.sleep(for: .seconds(shadowPause))
                guard !Task.isCancelled else { return }
                if !silent { DSHaptics.shadowTick() }
            }

            // BACKFILL: Azure pronunciation scoring; until then a completed
            // shadow logs as a rep with no score and no FSRS effect.
            self.context.insert(DrillEvent(
                sentenceId: line.lineId, axis: .shadow, correct: true, latencyMs: 0
            ))
            try? self.context.save()
            self.advanceShadow()
        }
    }

    /// Skips the rest of the current shadow line (mirror parity).
    func skipShadowItem() {
        guard stage == .shadow else { return }
        stepTask?.cancel()
        audio.stop()
        advanceShadow()
    }

    private func advanceShadow() {
        if shadowIndex + 1 < shadowLines.count {
            transition { self.shadowIndex += 1 }
            startShadowItem()
        } else {
            backToTranscript()
        }
    }

    // MARK: Spine

    /// Every answered question lands in the one spine as a comprehension
    /// event on its imported question Sentence; if a store somehow lacks it,
    /// the DrillEvent is still recorded directly.
    private func recordComprehension(questionNumber: Int, correct: Bool) {
        let latencyMs = max(Int(Date.now.timeIntervalSince(questionShownAt) * 1000), 0)
        let id = "\(episode.id)_q\(questionNumber)"
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
            assertionFailure("No Sentence imported for episode question \(id)")
            context.insert(DrillEvent(
                sentenceId: id, axis: .comprehension,
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

    /// All stage/step mutations animate with the DS baseline spring.
    private func transition(_ mutate: @escaping () -> Void) {
        withAnimation(DSMotion.spring, mutate)
    }
}
