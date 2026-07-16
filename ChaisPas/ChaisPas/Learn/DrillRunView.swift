import SwiftData
import SwiftUI

/// The drill run every Learn player ends in (PLAN2 §5.1): SessionEngine in
/// its single-phase configuration — the Construction choreography (English
/// prompt with audio → speak-pause → native reveal → grade) over one unit's
/// drills, every grade feeding DrillEvents/FSRS/mastery through the one spine.
struct DrillRunView: View {
    @Environment(\.modelContext) private var modelContext

    let unit: ConceptNode
    /// Called when the run is over (summary confirmed) or abandoned (X).
    let onFinished: () -> Void

    @State private var engine: SessionEngine?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let engine {
                content(engine)
            }
        }
        .task {
            guard engine == nil else { return }
            let engine = SessionEngine(context: modelContext, mode: .drillRun(unit: unit))
            self.engine = engine
            engine.start()
        }
    }

    private func content(_ engine: SessionEngine) -> some View {
        VStack(spacing: 0) {
            chrome(engine)

            Group {
                switch engine.phase {
                case .summary:
                    DrillRunSummaryView(engine: engine, onDone: onFinished)
                default:
                    if let sentence = engine.currentSentence {
                        DrillStageView(engine: engine, sentence: sentence)
                            .id(sentence.id)
                    } else {
                        // Nothing to drill (empty pool) — shouldn't happen with
                        // pack content, but never strand the user.
                        DrillRunSummaryView(engine: engine, onDone: onFinished)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    /// Same persistent chrome as the session: what you're drilling, a way
    /// out, and the hairline.
    private func chrome(_ engine: SessionEngine) -> some View {
        VStack(spacing: DSSpacing.md) {
            HStack {
                Text("DRILL · \(unit.title.uppercased())")
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    engine.end()
                    onFinished()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("drill-close")
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

// MARK: - Summary

private struct DrillRunSummaryView: View {
    let engine: SessionEngine
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
                    row("Items", "\(engine.itemsCompleted)")
                    if engine.gradedCount > 0 {
                        row("Accuracy",
                            "\(Int((Double(engine.correctCount) / Double(engine.gradedCount) * 100).rounded()))%")
                    }
                    row("Minutes", "\(max(Int(Date.now.timeIntervalSince(engine.startedAt)) / 60, 1))")
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

    private func row(_ label: String, _ value: String) -> some View {
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
