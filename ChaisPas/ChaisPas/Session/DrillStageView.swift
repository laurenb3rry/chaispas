import SwiftUI

/// The production-drill center stage (prompt → pause → reveal → grade), shared
/// by the Construction session and the Learn drill runs. Phase 16: composed as
/// one block — a mono phase eyebrow over a hairline, the prompt/French/street
/// readout, and the action footer bound directly beneath it, the whole group
/// optically centred. Views only render engine state and forward taps.
struct DrillStageView: View {
    let engine: SessionEngine
    let sentence: Sentence

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealed: Bool { engine.drillStep != .listening }

    private var gradeTint: Color? {
        if case .graded(let correct) = engine.drillStep {
            return correct ? DSColor.gradeSuccess : DSColor.gradeFailure
        }
        return nil
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }

    var body: some View {
        VStack(spacing: 0) {
            // The readout and its action footer are ONE centred block — read
            // the answer, grade right below it. Equal spacers keep the block
            // deliberately composed rather than marooned dead-centre.
            Spacer(minLength: DSSpacing.lg)

            readout
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)

            Spacer().frame(height: DSSpacing.xxl)

            footer
                .padding(.horizontal, DSSpacing.margin)

            Spacer(minLength: DSSpacing.lg)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !revealed { engine.reveal() }
        }
    }

    // MARK: Readout

    private var readout: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Eyebrow(revealed ? "Reveal" : "Say it in French", micro: true)
            Hairline()
                .padding(.bottom, DSSpacing.sm)

            // The English cue: prominent while speaking, recedes on reveal.
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
                            Eyebrow("On the street", micro: true)
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
                .padding(.top, DSSpacing.xs)
                .transition(revealTransition)
            }
        }
    }

    // MARK: Footer (bound beneath the readout — grade, or the listening state)

    @ViewBuilder
    private var footer: some View {
        if revealed {
            HStack(spacing: DSSpacing.md) {
                Button { engine.replayAudio() } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(DSColor.surface, in: Circle())
                }
                .buttonStyle(.pressable)
                gradeButton("Missed it", correct: false)
                gradeButton("Got it", correct: true)
            }
            .transition(revealTransition)
        } else {
            VStack(spacing: DSSpacing.md) {
                BreathingIndicator()
                if engine.speechActive, let spoken = engine.spokenText {
                    SpokenTranscriptView(spoken: spoken, targets: nil)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                Text("tap to reveal")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }

    private func gradeButton(_ label: String, correct: Bool) -> some View {
        Button { engine.grade(correct: correct) } label: {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(correct ? DSColor.background : DSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(correct ? DSColor.accent : DSColor.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(engine.drillStep != .revealed)
    }
}

// MARK: - Breathing indicator

/// Quiet pulse marking "your turn to speak" — deliberately not a live
/// waveform. Honours Reduce Motion (holds a static dot).
struct BreathingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(DSColor.accent)
            .frame(width: 11, height: 11)
            .scaleEffect(expanded ? 1.6 : 1)
            .opacity(expanded ? 0.45 : 1)
            .animation(reduceMotion ? nil :
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: expanded)
            .onAppear { if !reduceMotion { expanded = true } }
            .frame(height: 22)
    }
}
