import SwiftData
import SwiftUI

/// Listen mode index (PLAN2 §5.4): episodes grouped by level A–D with
/// durations and best scores. Each row opens the staged player.
struct ListenIndexView: View {
    @Query(sort: [SortDescriptor(\ListenEpisode.level), SortDescriptor(\ListenEpisode.id)])
    private var episodes: [ListenEpisode]

    @State private var playing: ListenEpisode?

    private static let levelBlurbs = [
        "A": "slower street, short exchanges",
        "B": "natural pace",
        "C": "fast, fillers creep in",
        "D": "full speed, fillers and all",
    ]

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    IndexHeader(title: "Listen", subtitle: "the comprehension gym")
                    ForEach(levels, id: \.self) { level in
                        levelSection(level)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.vertical, DSSpacing.xl)
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { episode in
            ListenPlayerView(episode: episode)
        }
    }

    private var levels: [String] {
        Array(Set(episodes.map(\.level))).sorted()
    }

    private func levelSection(_ level: String) -> some View {
        let group = episodes.filter { $0.level == level }
        var detail = "\(group.count) episodes"
        if let blurb = Self.levelBlurbs[level] { detail += " · \(blurb)" }
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            IndexSectionHeader(title: "Level \(level)", detail: detail)
            VStack(spacing: 0) {
                ForEach(group) { episode in
                    episodeRow(episode)
                    if episode.id != group.last?.id {
                        RowDivider()
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: ListenEpisode) -> some View {
        Button { playing = episode } label: {
            HStack(spacing: DSSpacing.md) {
                Text(episode.level)
                    .font(DSType.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let best = bestScoreLabel(episode) {
                        Text(best)
                            .font(DSType.caption.monospacedDigit())
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer()
                Text(DSFormat.duration(episode.durationSec))
                    .font(DSType.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("episode-\(episode.id)")
    }

    private func bestScoreLabel(_ episode: ListenEpisode) -> String? {
        guard let best = episode.bestScore else { return nil }
        let total = (try? episode.decodedQuestions().count) ?? 0
        return total > 0 ? "best \(best)/\(total)" : "best \(best)"
    }
}

#Preview {
    NavigationStack { ListenIndexView() }
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
