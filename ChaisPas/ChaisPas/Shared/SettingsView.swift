import SwiftUI

/// Minimal settings surface (phase 14): re-running the placement assessment
/// (PLAN2 §6) and, since phase 15, the speech-transcript toggle (§7). Phase 16:
/// de-carded — hairline sections, mono metadata.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var runningPlacement = false
    @State private var summary = PlacementGate.lastSummary
    /// Default on; the engines read it at their next construction, so the
    /// change takes effect on the next drill/scenario opened.
    @AppStorage(SpeechTranscriber.enabledKey) private var showTranscript = true

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
              VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Settings")
                        .font(DSType.largeTitle)
                        .tracking(DSType.largeTitleTracking)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("settings-close")
                }

                gradingSection
                placementSection

                Spacer(minLength: DSSpacing.xxl)
              }
              .padding(.horizontal, DSSpacing.margin)
              .padding(.top, DSSpacing.xl)
              .padding(.bottom, DSSpacing.xxl)
            }
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

    // MARK: Placement (§6)

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: "Placement")
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            Button { runningPlacement = true } label: {
                HStack(spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(summary == nil ? "Run placement" : "Run placement again")
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textPrimary)
                        if let summary {
                            Text("last run \(summary.completedAt.formatted(.dateTime.month(.wide).day()))")
                                .font(DSType.caption)
                                .foregroundStyle(DSColor.textSecondary)
                            MonoData("Listen \(summary.listenLevel) · Read tier \(summary.readTier)")
                        } else {
                            Text("an eight-minute reading of where to start")
                                .font(DSType.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    Spacer(minLength: DSSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .padding(.vertical, DSSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("settings-run-placement")
            Text("Recalibration only raises starting points — nothing you've earned is lost.")
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.top, DSSpacing.sm)
        }
    }

    // MARK: Speech (§7)

    private var gradingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: "Speech")
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            Toggle(isOn: $showTranscript) {
                Text("Show what I say")
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
            }
            .tint(DSColor.accent)
            .padding(.vertical, DSSpacing.md)
            .accessibilityIdentifier("settings-speech-toggle")
            Text(showTranscript
                 ? "While you speak, the mic shows what it heard — transcribed on-device — so you can grade yourself against the answer. It never grades or advances for you."
                 : "The mic stays off; drills just wait for you to speak and tap.")
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
            if showTranscript, SpeechTranscriber.deniedBySystem {
                Text("Microphone or speech access is off in iOS Settings, so there's no transcript until you re-enable it.")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.gradeFailure)
                    .padding(.top, DSSpacing.xs)
            }
        }
    }
}

#Preview {
    SettingsView()
}
