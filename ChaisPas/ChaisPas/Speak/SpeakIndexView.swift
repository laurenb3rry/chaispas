import SwiftData
import SwiftUI

/// Speak mode index (PLAN2 §5.2): the 12 everyday-France scenarios, ordered
/// easy → hard. Cards are browsable now; the dialogue player is phase 11.
struct SpeakIndexView: View {
    @Query(sort: [SortDescriptor(\Scenario.difficulty), SortDescriptor(\Scenario.id)])
    private var scenarios: [Scenario]

    @State private var comingSoon: ModeStub?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    IndexHeader(title: "Speak", subtitle: "everyday France, street register first")
                        .padding(.bottom, DSSpacing.md)
                    ForEach(scenarios) { scenario in
                        scenarioCard(scenario)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.vertical, DSSpacing.xl)
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $comingSoon) { ComingSoonSheet(stub: $0) }
    }

    private func scenarioCard(_ scenario: Scenario) -> some View {
        Button { comingSoon = .speak } label: {
            HStack(alignment: .top, spacing: DSSpacing.lg) {
                Image(systemName: scenario.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DSColor.accent)
                    .frame(width: 32)
                    .padding(.top, DSSpacing.xs)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(scenario.title)
                        .font(DSType.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(scenario.settingBlurb)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.leading)
                    Text(meta(scenario))
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary.opacity(0.7))
                        .padding(.top, DSSpacing.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func meta(_ scenario: Scenario) -> String {
        let played = scenario.completedCount == 0
            ? "not played yet"
            : "played \(scenario.completedCount)×"
        return "level \(scenario.difficulty) · \(played)"
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
