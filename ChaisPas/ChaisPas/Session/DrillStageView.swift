import SwiftUI

/// The production-drill center stage (prompt → pause → reveal → grade),
/// shared by the Construction session and the Learn drill runs — one
/// choreography, four doors. Views only render engine state and forward taps.
struct DrillStageView: View {
    let engine: SessionEngine
    let sentence: Sentence

    private var revealed: Bool { engine.drillStep != .listening }

    private var gradeTint: Color? {
        if case .graded(let correct) = engine.drillStep {
            return correct ? DSColor.gradeSuccess : DSColor.gradeFailure
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                // The English cue: center stage while speaking, then it
                // yields the stage to the French.
                Text(sentence.english)
                    .font(revealed ? DSType.englishPrompt : DSType.stagePrompt)
                    .foregroundStyle(revealed ? DSColor.textSecondary : DSColor.textPrimary)

                if revealed {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        Text(sentence.frenchFormal)
                            .font(DSType.stageFrench)
                            .foregroundStyle(gradeTint ?? DSColor.textPrimary)
                        if sentence.frenchStreet != sentence.frenchFormal {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text("ON THE STREET")
                                    .font(DSType.caption.weight(.medium))
                                    .tracking(1.2)
                                    .foregroundStyle(DSColor.textSecondary)
                                Text(sentence.frenchStreet)
                                    .font(DSType.stageFrenchSecondary)
                                    .foregroundStyle(DSColor.accent)
                            }
                        }
                        if let spoken = engine.spokenText {
                            SpokenTranscriptView(
                                spoken: spoken,
                                targets: [sentence.frenchFormal, sentence.frenchStreet]
                            )
                            .transition(.opacity)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.margin)

            Spacer()

            footer
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !revealed { engine.reveal() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        ZStack {
            if revealed {
                HStack(spacing: DSSpacing.md) {
                    Button { engine.replayAudio() } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(width: 52, height: 52)
                            .background(DSColor.surface, in: Circle())
                    }
                    gradeButton("Missed it", correct: false)
                    gradeButton("Got it", correct: true)
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            } else {
                VStack(spacing: DSSpacing.lg) {
                    BreathingIndicator()
                    if engine.speechActive, let spoken = engine.spokenText {
                        // Live mirror of what the mic is hearing.
                        SpokenTranscriptView(spoken: spoken, targets: nil)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    Text("say it in French — tap to reveal")
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
        .frame(height: 110, alignment: .bottom)
    }

    private func gradeButton(_ label: String, correct: Bool) -> some View {
        Button { engine.grade(correct: correct) } label: {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(correct ? DSColor.background : DSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(correct ? DSColor.accent : DSColor.surface, in: Capsule())
        }
        .disabled(engine.drillStep != .revealed)
    }
}

// MARK: - Breathing indicator

/// Quiet pulse marking "your turn to speak" — the §8 breathing indicator,
/// deliberately not a live waveform: the instrument shouldn't perform.
struct BreathingIndicator: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(DSColor.accent)
            .frame(width: 12, height: 12)
            .scaleEffect(expanded ? 1.6 : 1)
            .opacity(expanded ? 0.45 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: expanded)
            .onAppear { expanded = true }
            .frame(height: 24)
    }
}
