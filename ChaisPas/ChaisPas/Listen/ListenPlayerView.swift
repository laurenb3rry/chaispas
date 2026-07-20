import SwiftData
import SwiftUI

/// The Listen episode player (PLAN2 §5.4) — a focused listening instrument.
/// Stage 1 is deliberately austere: audio, a hairline, a pause control, and
/// nothing that could help. The transcript arrives only after the questions,
/// set at the 10c reading register, and stays on screen as the hub for the
/// optional slow pass and shadow.
struct ListenPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let episode: ListenEpisode

    @State private var engine: ListenEngine?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let engine {
                content(engine)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard engine == nil else { return }
            let engine = ListenEngine(episode: episode, context: modelContext)
            self.engine = engine
            engine.start()
        }
    }

    private func content(_ engine: ListenEngine) -> some View {
        VStack(spacing: 0) {
            chrome(engine)
            Group {
                switch engine.stage {
                case .cold:
                    ColdListenStageView(engine: engine)
                case .questions:
                    QuestionStageView(engine: engine)
                        .id(engine.questionIndex)
                case .transcript, .slow:
                    TranscriptStageView(engine: engine, onDone: { dismiss() })
                case .shadow:
                    ShadowStageView(engine: engine)
                        .id(engine.shadowIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    /// Same persistent chrome as every player: where you are, a way out,
    /// and the hairline (playback through the listens, then progress).
    private func chrome(_ engine: ListenEngine) -> some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Eyebrow(chromeLabel(engine), micro: true)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer()
                Button {
                    engine.end()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("listen-close")
            }
            .padding(.horizontal, DSSpacing.margin)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DSColor.surface)
                    Rectangle()
                        .fill(DSColor.accent)
                        .frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 2)
        }
        .padding(.top, DSSpacing.sm)
    }

    private func chromeLabel(_ engine: ListenEngine) -> String {
        let stage = switch engine.stage {
        case .cold: "Cold listen"
        case .questions: "Question \(engine.questionIndex + 1) of \(engine.questions.count)"
        case .transcript: "The transcript"
        case .slow: "Slow pass"
        case .shadow: "Shadow"
        }
        return "Listen · \(stage)"
    }
}

// MARK: - Stage 1: cold listen

private struct ColdListenStageView: View {
    let engine: ListenEngine

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The whole stage: a pulse while it plays. Nothing to read.
            VStack(spacing: DSSpacing.lg) {
                if engine.playback == .finished {
                    Text("Alors — what did you catch?")
                        .font(DSType.title)
                        .foregroundStyle(DSColor.textPrimary)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                } else {
                    BreathingIndicator()
                    Text("just listen")
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }

            Spacer()

            footer
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: DSSpacing.md) {
            if engine.playback == .finished {
                Button { engine.toQuestions() } label: {
                    Text("The questions")
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DSColor.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("to-questions")
                Button { engine.replayCold() } label: {
                    Text("Listen again")
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DSColor.surface, in: Capsule())
                }
                .buttonStyle(.pressable)
            } else {
                Button {
                    engine.playback == .paused
                        ? engine.resumePlayback() : engine.pausePlayback()
                } label: {
                    Image(systemName: engine.playback == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: 64, height: 64)
                        .background(DSColor.surface, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("playback-toggle")
            }
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
    }
}

// MARK: - Stage 2: questions

private struct QuestionStageView: View {
    let engine: ListenEngine

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let question = engine.currentQuestion {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Text(question.question)
                        .font(DSType.stagePrompt)
                        .foregroundStyle(DSColor.textPrimary)

                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(Array(question.options.enumerated()), id: \.offset) {
                            index, option in
                            optionButton(option, index: index, question: question)
                            Hairline()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
            }

            Spacer()
        }
    }

    /// Quiet grading: the tapped option's text takes the grade tint; on a
    /// miss the correct option turns green alongside it. No confetti.
    private func optionButton(
        _ option: String, index: Int, question: ComprehensionQuestion
    ) -> some View {
        let answered = engine.selectedAnswer != nil
        let isChosen = engine.selectedAnswer == index
        let isCorrect = index == question.answerIndex
        let tint: Color? = if answered && isChosen {
            isCorrect ? DSColor.gradeSuccess : DSColor.gradeFailure
        } else if answered && isCorrect {
            DSColor.gradeSuccess
        } else {
            nil
        }
        let letters = ["a", "b", "c", "d", "e"]
        return Button { engine.answer(index) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                Text(letters[min(index, letters.count - 1)])
                    .font(DSType.monoMicro).tracking(DSType.microTracking)
                    .foregroundStyle(tint ?? DSColor.textTertiary)
                    .frame(width: 14, alignment: .leading)
                Text(option)
                    .font(DSType.body.weight(answered && isCorrect ? .medium : .regular))
                    .foregroundStyle(tint ?? DSColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(answered)
        .accessibilityIdentifier("question-option-\(index)")
    }
}

// MARK: - Stages 3 + 4: transcript hub (slow pass plays over it)

private struct TranscriptStageView: View {
    let engine: ListenEngine
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, DSSpacing.lg)
                    ForEach(Array(engine.lines.enumerated()), id: \.element.lineId) {
                        index, line in
                        lineRow(line)
                        if index < engine.lines.count - 1 {
                            RowDivider()
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.lg)
            }

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(engine.episode.title)
                .font(DSType.title)
                .foregroundStyle(DSColor.textPrimary)
            if engine.questionsCompleted {
                MonoData("\(engine.correctCount) of \(engine.questions.count) questions · tap a line to hear it",
                         color: DSColor.textSecondary)
            }
        }
    }

    /// The 10c reading register: French primary at reading scale, gloss in
    /// caption under it, the speaker as a quiet tracked label. The whole row
    /// replays its line.
    private func lineRow(_ line: TranscriptLine) -> some View {
        let playing = engine.playingLineId == line.lineId
        return Button { engine.playLine(line) } label: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Eyebrow(speakerLabel(line), color: DSColor.textTertiary, micro: true)
                Text(line.frenchStreet)
                    .font(DSType.frenchCompact)
                    .foregroundStyle(playing ? DSColor.accent : DSColor.textPrimary)
                Text(line.english)
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(engine.stage == .slow)
    }

    private func speakerLabel(_ line: TranscriptLine) -> String {
        let index = line.speaker - 1
        return engine.episode.speakerLabels.indices.contains(index)
            ? engine.episode.speakerLabels[index] : "Voix \(line.speaker)"
    }

    /// Hub actions — or the slow pass's playback controls while it runs.
    @ViewBuilder
    private var footer: some View {
        VStack(spacing: DSSpacing.md) {
            if engine.stage == .slow {
                HStack(spacing: DSSpacing.md) {
                    Button {
                        engine.playback == .paused
                            ? engine.resumePlayback() : engine.pausePlayback()
                    } label: {
                        Image(systemName: engine.playback == .paused
                              || engine.playback == .finished ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(width: 48, height: 48)
                            .background(DSColor.surface, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(engine.playback == .finished)
                    Button { engine.backToTranscript() } label: {
                        Text("Back to the transcript")
                            .font(DSType.body.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(DSColor.surface, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("end-slow-pass")
                }
            } else {
                HStack(spacing: DSSpacing.md) {
                    hubAction("Re-listen slow", identifier: "slow-pass") {
                        engine.toSlowPass()
                    }
                    hubAction("Shadow two lines", identifier: "to-shadow") {
                        engine.toShadow()
                    }
                }
                Button(action: onDone) {
                    Text("Done")
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DSColor.accent, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.md)
        .padding(.bottom, DSSpacing.xxl)
        .background(DSColor.background)
    }

    private func hubAction(
        _ label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DSColor.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Stage 5: shadow (street-mirror register)

private struct ShadowStageView: View {
    let engine: ListenEngine

    private var shadowing: Bool {
        if case .shadow = engine.shadowStep { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let line = engine.currentShadowLine {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Eyebrow(engine.shadowStep.label, micro: true)
                        .contentTransition(.opacity)

                    Text(line.frenchStreet)
                        .font(DSType.stageFrench)
                        .foregroundStyle(DSColor.accent)

                    Text(line.english)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
            }

            Spacer()

            ZStack {
                if shadowing {
                    VStack(spacing: DSSpacing.lg) {
                        BreathingIndicator()
                        Text("say it out loud, keep the pace")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .transition(.opacity)
                } else {
                    Button("Skip") { engine.skipShadowItem() }
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("shadow-skip")
                }
            }
            .padding(.bottom, DSSpacing.xxl)
            .frame(height: 110, alignment: .bottom)
        }
    }
}
