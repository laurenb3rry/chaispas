import SwiftData
import SwiftUI

/// The placement assessment surface (PLAN2 §6): a calm instrument
/// calibration, not a test. Skippable on first run, re-runnable from
/// Settings; either way it ends in `onDone` — the caller decides what's
/// behind it.
struct PlacementView: View {
    @Environment(\.modelContext) private var modelContext

    let isFirstRun: Bool
    let onDone: () -> Void

    @State private var engine: PlacementEngine?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let engine {
                flow(engine)
            } else {
                intro
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Intro (the skippable first screen)

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Eyebrow("Calibration")
                Text("Let's take a reading.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                Text("About eight minutes: listen and tap what it means, say some French out loud, and call real words from fakes. It sets where everything starts — nothing to pass, nothing to lose.")
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, DSSpacing.margin)
            Spacer()
            VStack(spacing: DSSpacing.md) {
                PrimaryButton("Begin") {
                    let engine = PlacementEngine(context: modelContext)
                    engine.start()
                    withAnimation(DSMotion.spring) { self.engine = engine }
                }
                .accessibilityIdentifier("placement-begin")
                Button(action: onDone) {
                    Text(isFirstRun ? "Not now — just start" : "Not now")
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("placement-skip")
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.xxl)
        }
    }

    // MARK: Flow

    private func flow(_ engine: PlacementEngine) -> some View {
        VStack(spacing: 0) {
            chrome(engine)
            Group {
                if engine.module == .summary {
                    summary(engine)
                } else if engine.awaitingStart {
                    moduleIntro(engine)
                } else {
                    switch engine.module {
                    case .staircase: staircaseStage(engine)
                    case .production: productionStage(engine)
                    case .vocab: vocabStage(engine)
                    case .summary: EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .offset(y: 12)))
        }
    }

    private func chrome(_ engine: PlacementEngine) -> some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Eyebrow("Calibration · \(moduleLabel(engine.module))", micro: true)
                Spacer()
                Button {
                    engine.abandon()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("placement-close")
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

    private func moduleLabel(_ module: PlacementEngine.Module) -> String {
        switch module {
        case .staircase: "Listen"
        case .production: "Speak"
        case .vocab: "Words"
        case .summary: "Done"
        }
    }

    // MARK: Module intros (user-paced — no surprise audio)

    private func moduleIntro(_ engine: PlacementEngine) -> some View {
        let (title, line) = switch engine.module {
        case .staircase: (
            "Listen.",
            "French plays, climbing in speed and register. Tap what it means. Wherever it stops, that's the reading — misses are information."
        )
        case .production: (
            "Speak.",
            "An English cue: say it in French, out loud, then check yourself against the native line. Blank is a data point, not a failure."
        )
        default: (
            "Words.",
            "Real French word, or not? Trust your gut — some of these are fakes."
        )
        }
        return VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text(title)
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                Text(line)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, DSSpacing.margin)
            Spacer()
            PrimaryButton("Ready") { engine.beginModule() }
                .accessibilityIdentifier("placement-ready")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
        }
    }

    // MARK: Staircase (type what you hear)

    @ViewBuilder
    private func staircaseStage(_ engine: PlacementEngine) -> some View {
        if let item = engine.currentStaircaseItem {
            StaircaseTranscriptionStage(engine: engine, item: item)
                .id(engine.staircaseIndex)
        }
    }

    // MARK: Elicited production (say it, then check yourself)

    @ViewBuilder
    private func productionStage(_ engine: PlacementEngine) -> some View {
        if let item = engine.currentProductionItem {
            let revealed = engine.productionStep == .revealed
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Text(item.sentence.english)
                        .font(revealed ? DSType.englishPrompt : DSType.stagePrompt)
                        .foregroundStyle(revealed ? DSColor.textSecondary : DSColor.textPrimary)
                    if revealed {
                        VStack(alignment: .leading, spacing: DSSpacing.lg) {
                            Text(item.sentence.frenchFormal)
                                .font(DSType.stageFrench)
                                .foregroundStyle(DSColor.textPrimary)
                            if item.sentence.frenchStreet != item.sentence.frenchFormal {
                                Text(item.sentence.frenchStreet)
                                    .font(DSType.stageFrenchSecondary)
                                    .foregroundStyle(DSColor.accent)
                            }
                            if let spoken = engine.spokenText {
                                SpokenTranscriptView(
                                    spoken: spoken,
                                    targets: [item.sentence.frenchFormal,
                                              item.sentence.frenchStreet]
                                )
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 14)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
                Spacer()
                ZStack {
                    if revealed {
                        HStack(spacing: DSSpacing.md) {
                            Button { engine.replayProductionAudio() } label: {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(DSColor.textPrimary)
                                    .frame(width: 48, height: 48)
                                    .background(DSColor.surface, in: Circle())
                            }
                            .buttonStyle(.pressable)
                            productionGrade(engine, "Not yet", correct: false)
                            productionGrade(engine, "Got it", correct: true)
                        }
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    } else {
                        Button { engine.revealProduction() } label: {
                            VStack(spacing: DSSpacing.lg) {
                                BreathingIndicator()
                                if engine.speechActive, let spoken = engine.spokenText {
                                    SpokenTranscriptView(spoken: spoken, targets: nil)
                                        .frame(maxWidth: .infinity)
                                        .multilineTextAlignment(.center)
                                }
                                Text("say it in French — tap to check")
                                    .font(DSType.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("placement-reveal")
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
                .frame(height: 110, alignment: .bottom)
            }
            .id(engine.productionIndex)
        }
    }

    private func productionGrade(
        _ engine: PlacementEngine, _ label: String, correct: Bool
    ) -> some View {
        Button { engine.gradeProduction(correct: correct) } label: {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(correct ? DSColor.background : DSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(correct ? DSColor.accent : DSColor.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(correct ? "placement-got-it" : "placement-not-yet")
    }

    // MARK: Vocab yes/no

    @ViewBuilder
    private func vocabStage(_ engine: PlacementEngine) -> some View {
        if let item = engine.currentVocabItem {
            VStack(spacing: 0) {
                Spacer()
                Text(item.text)
                    .font(DSType.stageFrench)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                // Two equal surfaces — the design must not hint at the
                // answer before the tap; the tapped one grades itself after.
                HStack(spacing: DSSpacing.md) {
                    vocabButton(engine, "not a word", saidWord: false)
                    vocabButton(engine, "a real word", saidWord: true)
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
            }
            .id(engine.vocabIndex)
        }
    }

    private func vocabButton(
        _ engine: PlacementEngine, _ label: String, saidWord: Bool
    ) -> some View {
        // The chosen button's letters grade the call: green when right,
        // red when not; the other button stays quiet.
        let tint: Color = if engine.vocabSelection == saidWord,
                             let correct = engine.vocabWasCorrect {
            correct ? DSColor.gradeSuccess : DSColor.gradeFailure
        } else {
            DSColor.textPrimary
        }
        return Button { engine.answerVocab(saidWord: saidWord) } label: {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DSColor.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(engine.vocabSelection != nil)
        .accessibilityIdentifier(saidWord ? "placement-word-yes" : "placement-word-no")
    }

    // MARK: Summary (the reading)

    private func summary(_ engine: PlacementEngine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("Calibrated.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                // The reading itself is the point of the screen — the same
                // line Settings will remember.
                if let result = engine.result {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Eyebrow("Your level")
                        Text("Listen \(result.listenLevel) · Read tier \(result.readTier)")
                            .font(DSType.title)
                            .foregroundStyle(DSColor.accent)
                        Text(result.vocabEstimate > 0
                             ? "≈\(result.vocabEstimate) words recognized"
                             : "vocabulary starting fresh")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Text("Everything keeps adjusting as you work — this just sets the starting line.")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(3)
            }
            .padding(.horizontal, DSSpacing.margin)
            Spacer()
            PrimaryButton("Done", action: onDone)
                .accessibilityIdentifier("placement-done")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// One staircase rung: hear it, type it, check it. A child view so the
/// field's text and focus reset with the parent's per-rung `.id`.
private struct StaircaseTranscriptionStage: View {
    let engine: PlacementEngine
    let item: PlacementEngine.StaircaseItem

    @State private var typed = ""
    @FocusState private var focused: Bool

    private var result: Bool? {
        if case .result(let matched) = engine.staircaseStep { return matched }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Eyebrow(item.register.label)
                Button { engine.replayStaircaseAudio() } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 17, weight: .medium))
                        Text("hear it again")
                            .font(DSType.caption)
                    }
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.lg)
                    .frame(height: 44)
                    .background(DSColor.surface, in: Capsule())
                }
                .accessibilityIdentifier("placement-replay")
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.top, DSSpacing.xxl)

            Spacer()

            Group {
                if let result {
                    resultState(matched: result)
                } else {
                    inputState
                }
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.xl)
            .transition(.opacity.combined(with: .offset(y: 10)))
        }
    }

    private var inputState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            TextField("type what you heard", text: $typed)
                .font(DSType.frenchCompact)
                .foregroundStyle(DSColor.textPrimary)
                .tint(DSColor.accent)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { engine.submitStaircase(typed) }
                .padding(DSSpacing.lg)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("placement-answer")
            PrimaryButton("Check") { engine.submitStaircase(typed) }
                .accessibilityIdentifier("placement-submit")
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func resultState(matched: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text(typed.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(DSType.frenchCompact)
                .foregroundStyle(matched ? DSColor.gradeSuccess : DSColor.gradeFailure)
            if !matched {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Eyebrow("It said", micro: true)
                    Text(item.answer)
                        .font(DSType.stageFrenchSecondary)
                        .foregroundStyle(DSColor.accent)
                }
                // The user's own call on a near-miss — quiet, but present.
                Button { engine.markStaircaseCloseEnough() } label: {
                    Text("close enough")
                        .font(DSType.caption)
                        .underline()
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("placement-close-enough")
                PrimaryButton("Next") { engine.advanceStaircase() }
                    .accessibilityIdentifier("placement-next")
            }
        }
    }
}

#Preview {
    PlacementView(isFirstRun: true, onDone: {})
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
