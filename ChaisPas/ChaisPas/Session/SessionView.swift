import SwiftData
import SwiftUI

/// The hero screen: one glance says what phase you're in and what to do.
/// Big center stage, minimal chrome, hairline progress — all state
/// transitions ride the DSMotion baseline spring (applied inside the engine).
struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var engine: SessionEngine?

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
            let engine = SessionEngine(context: modelContext)
            self.engine = engine
            engine.start()
        }
    }

    private func content(_ engine: SessionEngine) -> some View {
        VStack(spacing: 0) {
            chrome(engine)

            Group {
                switch engine.phase {
                case .warmRecall, .ladder, .spontaneous:
                    if let sentence = engine.currentSentence {
                        DrillStageView(engine: engine, sentence: sentence)
                            .id(sentence.id)
                    }
                case .conceptIntro:
                    if let concept = engine.newConcept {
                        ConceptIntroView(concept: concept) { engine.confirmIntro() }
                    }
                case .streetMirror:
                    if let sentence = engine.currentSentence {
                        StreetMirrorView(engine: engine, sentence: sentence)
                            .id(sentence.id)
                    }
                case .summary:
                    SummaryView(engine: engine) { dismiss() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    /// Top chrome: phase label, close, and the hairline progress —
    /// deliberately the only persistent UI.
    private func chrome(_ engine: SessionEngine) -> some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Text(engine.phase.label.uppercased())
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textSecondary)
                    .contentTransition(.opacity)
                Spacer()
                Button {
                    engine.end()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
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
}

// MARK: - Concept intro (MT-style framing, ≤15s read)
// (DrillStageView and BreathingIndicator live in DrillStageView.swift,
// shared with the Learn drill runs.)

private struct ConceptIntroView: View {
    let concept: ConceptNode
    let onContinue: () -> Void

    private var conceptTypeLabel: String {
        concept.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "+", with: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Text("TIER \(concept.tier) · \(conceptTypeLabel.uppercased())")
                        .font(DSType.caption.weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.top, DSSpacing.xxl)

                    Text(concept.title)
                        .font(DSType.largeTitle)
                        .tracking(DSType.largeTitleTracking)
                        .foregroundStyle(DSColor.textPrimary)

                    Text(concept.explanationText)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        ForEach(concept.examples.prefix(3), id: \.self) { example in
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text(example.english)
                                    .font(DSType.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                                Text(example.formal)
                                    .font(DSType.french)
                                    .foregroundStyle(DSColor.textPrimary)
                                if example.street != example.formal {
                                    Text(example.street)
                                        .font(DSType.french)
                                        .foregroundStyle(DSColor.accent)
                                }
                            }
                        }
                    }
                    .padding(.top, DSSpacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.margin)
            }

            Button(action: onContinue) {
                Text("Got it — let's build")
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DSColor.accent, in: Capsule())
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.xxl)
        }
    }
}

// MARK: - Street mirror (fast → slow → shadow ×2)

private struct StreetMirrorView: View {
    let engine: SessionEngine
    let sentence: Sentence

    private var shadowing: Bool {
        if case .shadow = engine.mirrorStep { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text(engine.mirrorStep.label.uppercased())
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textSecondary)
                    .contentTransition(.opacity)

                Text(sentence.frenchStreet)
                    .font(DSType.stageFrench)
                    .foregroundStyle(DSColor.accent)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if sentence.frenchFormal != sentence.frenchStreet {
                        Text(sentence.frenchFormal)
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Text(sentence.english)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.margin)

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
                    Button("Skip") { engine.skipMirrorItem() }
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.bottom, DSSpacing.xxl)
            .frame(height: 110, alignment: .bottom)
        }
    }
}

// MARK: - Summary

private struct SummaryView: View {
    let engine: SessionEngine
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("C'est fait.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    summaryRow("Items", "\(engine.itemsCompleted)")
                    if engine.gradedCount > 0 {
                        summaryRow(
                            "Accuracy",
                            "\(Int((Double(engine.correctCount) / Double(engine.gradedCount) * 100).rounded()))%"
                        )
                    }
                    summaryRow("Minutes", "\(max(Int(Date.now.timeIntervalSince(engine.startedAt)) / 60, 1))")
                    if engine.newConcept?.introduced == true {
                        summaryRow("New today", engine.targetConceptTitle)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.margin)

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DSColor.accent, in: Capsule())
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DSType.body)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
            Text(value)
                .font(DSType.body.monospacedDigit())
                .foregroundStyle(DSColor.textPrimary)
        }
    }
}

#Preview {
    SessionView()
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self, SessionLog.self],
            inMemory: true
        )
}
