import SwiftData
import SwiftUI

/// v2 root: a scrolling library (PLAN2 §8). All four modes are visible and
/// browsable from here — showing the depth is the anti-"stuck" fix. Nothing
/// is hard-locked; order arrives as soft recommendation only.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Scenario.difficulty), SortDescriptor(\Scenario.id)])
    private var scenarios: [Scenario]
    @Query(sort: [SortDescriptor(\ListenEpisode.level), SortDescriptor(\ListenEpisode.id)])
    private var episodes: [ListenEpisode]
    @Query(sort: [SortDescriptor(\Passage.tier), SortDescriptor(\Passage.id)])
    private var passages: [Passage]

    /// Live store counts for the Learn tiles.
    private struct LearnCounts {
        var constructionTotal = 0
        var constructionIntroduced = 0
        var verbs = 0
        var verbsMastered = 0
        var vocabPacks = 0
        var vocabMastered = 0
        var grammarLessons = 0
        var grammarMastered = 0
    }

    @State private var learn = LearnCounts()
    @State private var dueReviews = 0
    @State private var nextConceptTitle: String?
    @State private var showingSession = false
    @State private var showingDebug = false
    @State private var comingSoon: ModeStub?
    @State private var playingScenario: Scenario?
    @State private var playingEpisode: ListenEpisode?

    var body: some View {
        NavigationStack {
            ZStack {
                DSColor.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                        header
                        recommendedCard
                        learnSection
                        speakSection
                        readSection
                        listenSection
                    }
                    .padding(.top, DSSpacing.xl)
                    .padding(.bottom, DSSpacing.xxl)
                }
                StatusBarScrim()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .learn(let focus): LearnIndexView(focus: focus)
                case .speak: SpeakIndexView()
                case .read: ReadIndexView()
                case .listen: ListenIndexView()
                }
            }
        }
        .tint(DSColor.accent)
        .preferredColorScheme(.dark)
        // onAppear (not task) so counts also refresh when an index pops back
        .onAppear { refresh() }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) {
            SessionView()
        }
        .sheet(isPresented: $showingDebug) { DebugView() }
        .sheet(item: $comingSoon) { ComingSoonSheet(stub: $0) }
        .fullScreenCover(item: $playingScenario, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) { scenario in
            ScenarioPlayerView(scenario: scenario)
        }
        .fullScreenCover(item: $playingEpisode, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) { episode in
            ListenPlayerView(episode: episode)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textSecondary)
                Text("Chais pas.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
            }
            Spacer()
            // Out-of-the-way door to the debug screen
            Button { showingDebug = true } label: {
                Image(systemName: "ant")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DSSpacing.margin)
    }

    // MARK: Recommended today

    // Static placeholder composition — the real composer (FSRS-aware
    // round-robin, difficulty-matched picks) is phase 14. Tapping starts the
    // Learn unit (the working Construction session).
    private var recommendedCard: some View {
        Button { showingSession = true } label: {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Text("RECOMMENDED TODAY")
                        .font(DSType.caption.weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    if dueReviews > 0 {
                        Text(dueReviews == 1 ? "1 review due" : "\(dueReviews) reviews due")
                            .font(DSType.caption.monospacedDigit())
                            .foregroundStyle(DSColor.accent)
                    }
                }
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    recommendedRow("Learn", nextConceptTitle.map { "Construction · \($0)" }
                                            ?? "Construction · review run")
                    if let scenario = recommendedScenario {
                        recommendedRow("Speak", scenario.title)
                    }
                    if let episode = episodes.first {
                        recommendedRow("Listen", episode.title)
                    }
                }
                Text("tap to start the Learn unit")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.accent)
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recommended-today")
        .padding(.horizontal, DSSpacing.margin)
    }

    private var recommendedScenario: Scenario? {
        scenarios.min {
            ($0.completedCount, $0.difficulty, $0.id) < ($1.completedCount, $1.difficulty, $1.id)
        }
    }

    private func recommendedRow(_ mode: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(mode.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 48, alignment: .leading)
            Text(title)
                .font(DSType.body)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: Learn (the centerpiece — largest section)

    private var learnSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            LibrarySectionHeader(title: "Learn", detail: "four ways in",
                                 destination: .learn(nil))
                .accessibilityIdentifier("home-section-learn")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible())],
                spacing: DSSpacing.md
            ) {
                learnTile("Construction",
                          detail: "\(learn.constructionTotal) concepts · \(learn.constructionIntroduced) introduced",
                          focus: .construction)
                learnTile("Conjugation",
                          detail: "\(learn.verbs) verbs · \(learn.verbsMastered) mastered",
                          focus: .conjugation)
                learnTile("Vocabulary",
                          detail: "\(learn.vocabPacks) packs · \(learn.vocabMastered) mastered",
                          focus: .vocabulary)
                learnTile("Grammar",
                          detail: "\(learn.grammarLessons) lessons · \(learn.grammarMastered) mastered",
                          focus: .grammar)
            }
        }
        .padding(.horizontal, DSSpacing.margin)
    }

    private func learnTile(_ name: String, detail: String, focus: LearnSection) -> some View {
        NavigationLink(value: LibraryDestination.learn(focus)) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(name)
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.lg)
                Text(detail)
                    .font(DSType.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learn-tile-\(focus.rawValue)")
    }

    // MARK: Speak

    private var speakSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            LibrarySectionHeader(title: "Speak", detail: "\(scenarios.count) scenarios",
                                 destination: .speak)
                .accessibilityIdentifier("home-section-speak")
                .padding(.horizontal, DSSpacing.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(scenarios) { scenario in
                        scenarioCard(scenario)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
            }
        }
    }

    private func scenarioCard(_ scenario: Scenario) -> some View {
        Button { playingScenario = scenario } label: {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Image(systemName: scenario.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(DSColor.accent)
                Spacer(minLength: DSSpacing.sm)
                Text(scenario.title)
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(scenario.completedCount == 0
                     ? "not played yet"
                     : "played \(scenario.completedCount)×")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.lg)
            .frame(width: 168, height: 132, alignment: .topLeading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Read

    private var readSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            LibrarySectionHeader(title: "Read", detail: "\(passages.count) passages",
                                 destination: .read)
                .accessibilityIdentifier("home-section-read")
                .padding(.horizontal, DSSpacing.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(passages.prefix(10)) { passage in
                        passageCard(passage)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
            }
        }
    }

    private func passageCard(_ passage: Passage) -> some View {
        Button { comingSoon = .read } label: {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(passage.style.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(DSColor.textSecondary)
                Text(passage.title)
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("tier \(passage.tier) · \(passage.wordCount) words")
                    .font(DSType.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.lg)
            .frame(width: 160, height: 124, alignment: .topLeading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Listen

    private var listenSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            LibrarySectionHeader(title: "Listen", detail: "\(episodes.count) episodes",
                                 destination: .listen)
                .accessibilityIdentifier("home-section-listen")
            VStack(spacing: 0) {
                ForEach(episodes.prefix(6)) { episode in
                    episodeRow(episode)
                    if episode.id != episodes.prefix(6).last?.id {
                        RowDivider()
                    }
                }
            }
        }
        .padding(.horizontal, DSSpacing.margin)
    }

    private func episodeRow(_ episode: ListenEpisode) -> some View {
        Button { playingEpisode = episode } label: {
            HStack(spacing: DSSpacing.md) {
                Text(episode.level)
                    .font(DSType.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 8))
                Text(episode.title)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(DSFormat.duration(episode.durationSec))
                    .font(DSType.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private func refresh() {
        let nodes = (try? modelContext.fetch(FetchDescriptor<ConceptNode>())) ?? []
        let scores = (try? MasteryModel.productionScores(context: modelContext)) ?? [:]
        func mastered(_ group: [ConceptNode]) -> Int {
            group.filter { (scores[$0.id] ?? 0) >= MasteryModel.masteredThreshold }.count
        }

        // #Predicate can't filter on the ConceptType enum — bucket in memory
        var counts = LearnCounts()
        let v1 = nodes.filter { SessionPlanner.v1Types.contains($0.type) }
        counts.constructionTotal = v1.count
        counts.constructionIntroduced = v1.filter(\.introduced).count
        let conjugation = nodes.filter { $0.type == .conjugation }
        counts.verbs = conjugation.count
        counts.verbsMastered = mastered(conjugation)
        let vocab = nodes.filter { $0.type == .vocabPack }
        counts.vocabPacks = vocab.count
        counts.vocabMastered = mastered(vocab)
        let grammar = nodes.filter { $0.type == .grammar }
        counts.grammarLessons = grammar.count
        counts.grammarMastered = mastered(grammar)
        learn = counts

        let now = Date.now
        dueReviews = (try? modelContext.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.fsrsStability > 0 && $0.fsrsDue <= now }
        ))) ?? 0

        let unlocked = (try? MasteryModel.unlockedConceptIds(context: modelContext)) ?? []
        nextConceptTitle = v1
            .filter { unlocked.contains($0.id) && !$0.introduced }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }?
            .title
    }
}

#Preview {
    HomeView()
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
