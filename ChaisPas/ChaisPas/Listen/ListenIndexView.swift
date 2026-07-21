import SwiftData
import SwiftUI

/// Listen mode index (PLAN2 §5.4): episodes grouped by level A–D with
/// durations and best scores. Phase 16: de-carded — level as a mono marker,
/// full-bleed hairlines, mono metadata.
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
                        .padding(.horizontal, DSSpacing.margin)
                    ForEach(levels, id: \.self) { level in
                        levelSection(level)
                    }
                }
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxl)
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
        return VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: "Level \(level)", detail: detail)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(group.enumerated()), id: \.element.id) { index, episode in
                episodeRow(episode)
                if index < group.count - 1 { Hairline() }
            }
        }
    }

    private func episodeRow(_ episode: ListenEpisode) -> some View {
        Button { playing = episode } label: {
            HStack(spacing: DSSpacing.md) {
                Text(episode.level)
                    .font(DSType.monoMicro).tracking(DSType.microTracking)
                    .foregroundStyle(DSColor.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(episode.title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    if let best = bestScoreLabel(episode) {
                        MonoData(best)
                    }
                }
                Spacer(minLength: DSSpacing.md)
                MonoData(DSFormat.duration(episode.durationSec))
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
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
