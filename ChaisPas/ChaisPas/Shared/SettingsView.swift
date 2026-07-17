import SwiftUI

/// Minimal settings surface (phase 14): today its one real job is re-running
/// the placement assessment (PLAN2 §6). Grows only when something earns a row.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var runningPlacement = false
    @State private var summary = PlacementGate.lastSummary

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                HStack {
                    Text("Settings")
                        .font(DSType.title)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("settings-close")
                }

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    IndexSectionHeader(title: "Placement", detail: "")
                    Button { runningPlacement = true } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(summary == nil ? "Run placement" : "Run placement again")
                                .font(DSType.body)
                                .foregroundStyle(DSColor.textPrimary)
                            if let summary {
                                Text("last run \(summary.completedAt.formatted(.dateTime.month(.wide).day()))")
                                    .font(DSType.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                                Text("placement: Listen \(summary.listenLevel) · Read tier \(summary.readTier)")
                                    .font(DSType.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            } else {
                                Text("an eight-minute reading of where to start")
                                    .font(DSType.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSSpacing.lg)
                        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-run-placement")
                    Text("Recalibration only raises starting points — nothing you've earned is lost.")
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.top, DSSpacing.xs)
                }

                Spacer()
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.top, DSSpacing.xl)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $runningPlacement, onDismiss: {
            summary = PlacementGate.lastSummary
        }) {
            PlacementView(isFirstRun: false) {
                runningPlacement = false
            }
        }
    }

}

#Preview {
    SettingsView()
}
