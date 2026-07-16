import SwiftData
import SwiftUI

/// Grammar player (PLAN2 §5.1): the lesson explanation in the MT voice, then
/// the canonical examples with audio, then the drill run. Explanation and
/// examples are already on the ConceptNode; only the audio names derive from
/// the pack layout.
struct GrammarPlayerView: View {
    private enum Stage {
        case explanation, examples, drilling
    }

    @Environment(\.dismiss) private var dismiss

    let unit: ConceptNode

    @State private var stage = Stage.explanation
    @State private var packSections: [ContentPackV2.ExplanationSection]?
    @State private var playingKey: String?
    @State private var audio = AudioPlayer()
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            switch stage {
            case .explanation:
                explanationStage
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .examples:
                examplesStage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .drilling:
                DrillRunView(unit: unit) { dismiss() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            audio.configureSession()
            // structured explanations live in the pack, not SwiftData
            packSections = ContentPackV2.learnNode(id: unit.id, module: .grammar)?.explanation
        }
    }

    // MARK: Stage 1 — the explanation (MT voice)

    private var explanationStage: some View {
        VStack(spacing: 0) {
            PlayerChrome(caption: "GRAMMAR · TIER \(unit.tier)") { close() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Text(unit.title)
                        .font(DSType.largeTitle)
                        .tracking(DSType.largeTitleTracking)
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.top, DSSpacing.lg)

                    if let sections = packSections, !sections.isEmpty {
                        ExplanationSectionsView(sections: sections)
                    } else {
                        // fallback for any node the pack can't resolve
                        Text(unit.explanationText)
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineSpacing(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xl)
            }

            advanceButton("The examples") {
                withAnimation(DSMotion.spring) { stage = .examples }
            }
        }
    }

    // MARK: Stage 2 — canonical examples with audio

    private var examplesStage: some View {
        VStack(spacing: 0) {
            PlayerChrome(caption: "GRAMMAR · \(unit.title.uppercased())") { close() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(unit.examples.enumerated()), id: \.offset) { index, example in
                        exampleRow(example, index: index)
                        if index < unit.examples.count - 1 {
                            RowDivider()
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xl)
            }

            StartDrillButton {
                playTask?.cancel()
                audio.stop()
                withAnimation(DSMotion.spring) { stage = .drilling }
            }
        }
    }

    private func exampleRow(_ example: CanonicalExample, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(example.english)
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)

            exampleLine(example.formal, index: index, variant: "formal",
                        baseColor: DSColor.textPrimary)
            if example.street != example.formal {
                exampleLine(example.street, index: index, variant: "street_fast",
                            baseColor: DSColor.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DSSpacing.md)
    }

    /// Tap a line to hear it; it glows accent while playing.
    private func exampleLine(_ text: String, index: Int, variant: String,
                             baseColor: Color) -> some View {
        let key = "\(index)_\(variant)"
        return Button {
            play(ContentPackV2.exampleAudio(nodeId: unit.id, index: index,
                                            variant: variant), key: key)
        } label: {
            Text(text)
                .font(DSType.frenchCompact)
                .foregroundStyle(playingKey == key ? DSColor.accent : baseColor)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pieces

    private func advanceButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DSColor.accent, in: Capsule())
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
    }

    private func play(_ fileName: String, key: String) {
        playTask?.cancel()
        playTask = Task {
            withAnimation(DSMotion.spring) { playingKey = key }
            await audio.play(fileName: fileName, from: .v2Learn)
            guard !Task.isCancelled else { return }
            withAnimation(DSMotion.spring) { playingKey = nil }
        }
    }

    private func close() {
        playTask?.cancel()
        audio.stop()
        dismiss()
    }
}
