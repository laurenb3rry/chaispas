import SwiftData
import SwiftUI

/// Speak mode index (PLAN2 §5.2): the 12 everyday-France scenarios, ordered
/// easy → hard. Phase 16: de-carded into a sequence list — a mono index (real
/// easy→hard order), title + blurb, mono level marker, hairline rhythm.
struct SpeakIndexView: View {
    @Query(sort: [SortDescriptor(\Scenario.difficulty), SortDescriptor(\Scenario.id)])
    private var scenarios: [Scenario]

    @State private var playing: Scenario?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    IndexHeader(title: "Speak", subtitle: "everyday France · street register first")
                        .padding(.horizontal, DSSpacing.margin)

                    VStack(alignment: .leading, spacing: 0) {
                        IndexSectionHeader(title: "Scenarios", detail: "easiest first")
                            .padding(.horizontal, DSSpacing.margin)
                            .padding(.bottom, DSSpacing.sm)
                        Hairline(strong: true)
                        ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                            scenarioRow(index: index + 1, scenario: scenario)
                            if index < scenarios.count - 1 { Hairline() }
                        }
                    }
                }
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxl)
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { scenario in
            ScenarioPlayerView(scenario: scenario)
        }
    }

    private func scenarioRow(index: Int, scenario: Scenario) -> some View {
        Button { playing = scenario } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.lg) {
                Text(String(format: "%02d", index))
                    .font(DSType.monoData)
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textTertiary)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(scenario.title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(scenario.settingBlurb)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.sm)
                Eyebrow(marker(scenario), color: DSColor.textTertiary, micro: true)
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("scenario-\(scenario.id)")
    }

    private func marker(_ scenario: Scenario) -> String {
        scenario.completedCount == 0
            ? "LVL \(scenario.difficulty)"
            : "LVL \(scenario.difficulty) · \(scenario.completedCount)×"
    }
}

#Preview {
    NavigationStack { SpeakIndexView() }
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
