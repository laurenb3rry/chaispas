import SwiftData
import SwiftUI

/// The Speak scenario player (PLAN2 §5.2): a conversation, one exchange at a
/// time — not a chat-app skin. The other side's line holds the stage while it
/// plays and stays up, dimmed, as context through your reply; the reveal
/// choreography is the Construction drill's, with the registers flipped
/// (street is the star, the full form sits under it at reading scale).
struct ScenarioPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let scenario: Scenario

    @State private var engine: ScenarioEngine?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let engine {
                content(engine)
            }
        }
        .swipeDownToDismiss { engine?.end(); dismiss() }
        .preferredColorScheme(.dark)
        .task {
            guard engine == nil else { return }
            let engine = ScenarioEngine(scenario: scenario, context: modelContext)
            self.engine = engine
            engine.start()
        }
    }

    private func content(_ engine: ScenarioEngine) -> some View {
        VStack(spacing: 0) {
            chrome(engine)
            Group {
                if engine.step == .ended {
                    ScenarioSummaryView(
                        engine: engine,
                        onReplay: { replayDifferently(after: engine) },
                        onDone: { dismiss() }
                    )
                } else {
                    ScenarioStageView(engine: engine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Same persistent chrome as the drill runs: where you are, a way out,
    /// and the hairline.
    private func chrome(_ engine: ScenarioEngine) -> some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Eyebrow("Speak · \(scenario.title)", micro: true)
                    .lineLimit(1)
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
                .accessibilityIdentifier("speak-close")
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

    /// The end-screen CTA: same scenario, least-recently-played other variant.
    private func replayDifferently(after old: ScenarioEngine) {
        old.end()
        let variants = (try? scenario.decodedVariants()) ?? []
        let next = ScenarioEngine.nextVariant(
            from: variants,
            lastPlayed: scenario.variantLastPlayed,
            excluding: old.variantId
        )
        let fresh = ScenarioEngine(
            scenario: scenario, context: modelContext, variantId: next?.variantId
        )
        withAnimation(DSMotion.spring) { engine = fresh }
        fresh.start()
    }
}

// MARK: - Stage

private struct ScenarioStageView: View {
    let engine: ScenarioEngine

    private var isUserTurn: Bool { engine.userLine != nil }

    private var gradeTint: Color? {
        if case .userGraded(let correct) = engine.step {
            return correct ? DSColor.gradeSuccess : DSColor.gradeFailure
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                if let npc = engine.npcLine {
                    npcBlock(npc)
                        .id(npc.nodeId)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
                if let user = engine.userLine {
                    userBlock(user)
                        .id(user.nodeId)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.margin)

            Spacer()

            footer
        }
        // Tapping low ("tap to continue") advances the NPC line or reveals
        // your answer; tapping the NPC's French line (below) shows its
        // English instead — a child gesture that wins over this one.
        .contentShape(Rectangle())
        .onTapGesture { engine.advanceOrReveal() }
    }

    // The other side: French only while it plays — comprehension first.
    // Tap the French line to reveal its English beneath it; it then stays as
    // context. Replay controls only while it's their moment.
    private func npcBlock(_ npc: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(npc.frenchStreet)
                    .font(DSType.french)
                    .foregroundStyle(DSColor.textPrimary)
                if engine.npcGlossShown {
                    Text(npc.english)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            // Tap the line itself → its English (no-op once shown).
            .contentShape(Rectangle())
            .onTapGesture { engine.revealNPCEnglish() }
            if engine.step == .npcSpeaking || engine.step == .npcGlossed {
                HStack(spacing: DSSpacing.md) {
                    npcReplayButton("speaker.wave.2", slow: false,
                                    identifier: "npc-replay-fast")
                    npcReplayButton("tortoise", slow: true,
                                    identifier: "npc-replay-slow")
                }
            }
        }
        .opacity(isUserTurn ? 0.45 : 1)
    }

    private func npcReplayButton(
        _ symbol: String, slow: Bool, identifier: String
    ) -> some View {
        Button { engine.replayNPC(slow: slow) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(DSColor.surface, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(identifier)
    }

    // Your turn: the English intent holds center stage while you speak,
    // then yields to the French — street first, the full form under it at
    // the reading scale (the 10c example-pair register).
    private func userBlock(_ user: ScenarioNode) -> some View {
        let revealed = engine.step != .userListening
        return VStack(alignment: .leading, spacing: DSSpacing.xl) {
            Text(user.english)
                .font(revealed ? DSType.englishPrompt : DSType.stagePrompt)
                .foregroundStyle(revealed ? DSColor.textSecondary : DSColor.textPrimary)

            if revealed {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    Text(user.frenchStreet)
                        .font(DSType.stageFrench)
                        .foregroundStyle(gradeTint ?? DSColor.textPrimary)
                    if let formal = user.frenchFormal, formal != user.frenchStreet {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Eyebrow("In full", micro: true)
                            Text(formal)
                                .font(DSType.frenchCompact)
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                    if let spoken = engine.spokenText {
                        SpokenTranscriptView(
                            spoken: spoken,
                            targets: [user.frenchStreet, user.frenchFormal].compactMap { $0 }
                        )
                        .transition(.opacity)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 14)))
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        ZStack {
            switch engine.step {
            case .npcSpeaking:
                tapHint("tap to continue · tap the French for its meaning")
            case .npcGlossed:
                tapHint("tap to continue")
            case .userListening:
                VStack(spacing: DSSpacing.lg) {
                    BreathingIndicator()
                    if engine.speechActive, let spoken = engine.spokenText {
                        SpokenTranscriptView(spoken: spoken, targets: nil)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    Text("say it in French, then tap")
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .transition(.opacity)
            case .userRevealed, .userGraded:
                HStack(spacing: DSSpacing.md) {
                    Button { engine.replayUser() } label: {
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
                .transition(.opacity.combined(with: .offset(y: 10)))
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
        .frame(height: 110, alignment: .bottom)
    }

    private func tapHint(_ text: String) -> some View {
        Text(text)
            .font(DSType.caption)
            .foregroundStyle(DSColor.textSecondary)
            .transition(.opacity)
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
        .disabled(engine.step != .userRevealed)
    }
}

// MARK: - Summary

private struct ScenarioSummaryView: View {
    let engine: ScenarioEngine
    let onReplay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("Et voilà.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    row("Exchanges", "\(engine.exchangesCompleted)")
                    if engine.exchangesCompleted > 0 {
                        row("Accuracy",
                            "\(Int((Double(engine.correctCount) / Double(engine.exchangesCompleted) * 100).rounded()))%")
                    }
                    row("Minutes", "\(max(Int(Date.now.timeIntervalSince(engine.startedAt)) / 60, 1))")
                }
            }
            .padding(.horizontal, DSSpacing.margin)

            Spacer()

            VStack(spacing: DSSpacing.md) {
                Button(action: onReplay) {
                    Text("Replay — different variant")
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DSColor.surface, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("replay-variant")
                PrimaryButton("Done", action: onDone)
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Eyebrow(label)
            Spacer()
            Text(value)
                .font(DSType.monoData)
                .monospacedDigit()
                .foregroundStyle(DSColor.textPrimary)
        }
    }
}
