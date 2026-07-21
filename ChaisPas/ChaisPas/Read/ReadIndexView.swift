import SwiftData
import SwiftUI

/// Read mode index (PLAN2 §5.3): passages grouped by tier, style-labeled,
/// read/unread with last scores. Phase 16: de-carded — style as a mono
/// eyebrow, full-bleed hairlines, mono metadata.
struct ReadIndexView: View {

    @Query(sort: [SortDescriptor(\Passage.tier), SortDescriptor(\Passage.id)])
    private var passages: [Passage]

    @State private var reading: Passage?

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
                        .padding(.horizontal, DSSpacing.margin)
                    ForEach(tiers, id: \.self) { tier in
                        tierSection(tier)
                    }
                }
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxl)
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reading) { passage in
            ReaderView(passage: passage)
        }
    }

    private var tiers: [Int] {
        Array(Set(passages.map(\.tier))).sorted()
    }

    private func tierSection(_ tier: Int) -> some View {
        let group = passages.filter { $0.tier == tier }
        var detail = "\(group.count) passages"
        if let label = Self.tierLabels[tier] { detail += " · \(label)" }
        return VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: "Tier \(tier)", detail: detail)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(group.enumerated()), id: \.element.id) { index, passage in
                passageRow(passage)
                if index < group.count - 1 { Hairline() }
            }
        }
    }

    private func passageRow(_ passage: Passage) -> some View {
        Button { reading = passage } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Eyebrow(passage.style, color: DSColor.textTertiary, micro: true)
                    Text(passage.title)
                        .font(DSType.body)
                        .foregroundStyle(passage.read ? DSColor.textSecondary : DSColor.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.sm)
                if passage.read {
                    if let score = passage.lastScore {
                        MonoData("\(score)/\(questionCount(passage))")
                    }
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DSColor.textTertiary)
                } else {
                    MonoData("\(passage.wordCount) words")
                }
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("passage-\(passage.id)")
    }

    private func questionCount(_ passage: Passage) -> Int {
        (try? passage.decodedQuestions().count) ?? 0
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
