import SwiftData
import SwiftUI

/// Read mode index (PLAN2 §5.3): passages grouped by tier, style-labeled,
/// read/unread. Browsable now; the Reader is phase 13.
struct ReadIndexView: View {
    @Query(sort: [SortDescriptor(\Passage.tier), SortDescriptor(\Passage.id)])
    private var passages: [Passage]

    @State private var comingSoon: ModeStub?

    private static let tierLabels = [
        0: "short & simple",
        1: "getting going",
        2: "everyday texts",
        3: "dense & fast",
    ]

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    IndexHeader(title: "Read", subtitle: "generated pages in real-world styles")
                    ForEach(tiers, id: \.self) { tier in
                        tierSection(tier)
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

    private var tiers: [Int] {
        Array(Set(passages.map(\.tier))).sorted()
    }

    private func tierSection(_ tier: Int) -> some View {
        let group = passages.filter { $0.tier == tier }
        var detail = "\(group.count) passages"
        if let label = Self.tierLabels[tier] { detail += " · \(label)" }
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            IndexSectionHeader(title: "Tier \(tier)", detail: detail)
            VStack(spacing: 0) {
                ForEach(group) { passage in
                    passageRow(passage)
                    if passage.id != group.last?.id {
                        RowDivider()
                    }
                }
            }
        }
    }

    private func passageRow(_ passage: Passage) -> some View {
        Button { comingSoon = .read } label: {
            HStack(spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(passage.style.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(DSColor.textSecondary)
                    Text(passage.title)
                        .font(DSType.body)
                        .foregroundStyle(passage.read ? DSColor.textSecondary : DSColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if passage.read {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    Text("\(passage.wordCount) words")
                        .font(DSType.caption.monospacedDigit())
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.vertical, DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { ReadIndexView() }
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
