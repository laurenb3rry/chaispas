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
    @State private var nextConceptTitle: String?
    @State private var recommendation: DailyRecommendation?
    @State private var showingSession = false
    @State private var showingDebug = false
    @State private var showingSettings = false
    @State private var playingScenario: Scenario?
    @State private var playingEpisode: ListenEpisode?
    @State private var readingPassage: Passage?
    @State private var recommendedLearnUnit: ConceptNode?

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
        .sheet(isPresented: $showingSettings, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) {
            SettingsView()
        }
        .fullScreenCover(item: $recommendedLearnUnit, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) { unit in
            LearnUnitPlayerView(unit: unit)
        }
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
        .fullScreenCover(item: $readingPassage, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) { passage in
            ReaderView(passage: passage)
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
            // Out-of-the-way doors to settings and the debug screen
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home-settings")
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

    // MARK: Recommended today (the §5.5 composer)

    // Three rows, each one tap into its slot's player. Purely a suggestion:
    // the quiet segment hairline reflects today's DrillEvents from anywhere,
    // not obedience to these picks. No streaks, no guilt.
    private var recommendedCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("RECOMMENDED TODAY")
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer()
                if let recommendation, recommendation.doneCount > 0 {
                    Text("today · \(recommendation.doneCount) of 3")
                        .font(DSType.caption.monospacedDigit())
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                learnRow
                if let scenario = recommendation?.speak {
                    recommendedRow("Speak", scenario.title,
                                   done: recommendation?.speakDone == true,
                                   id: "recommended-speak") {
                        playingScenario = scenario
                    }
                }
                if let episode = recommendation?.listen {
                    recommendedRow("Listen", "\(episode.title) · level \(episode.level)",
                                   done: recommendation?.listenDone == true,
                                   id: "recommended-listen") {
                        playingEpisode = episode
                    }
                }
            }
            slotHairline
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, DSSpacing.margin)
    }

    @ViewBuilder
    private var learnRow: some View {
        let done = recommendation?.learnDone == true
        switch recommendation?.learn {
        case .review(let dueCount):
            recommendedRow(
                "Learn",
                "Construction · \(dueCount == 1 ? "1 review due" : "\(dueCount) reviews due")",
                done: done, id: "recommended-learn"
            ) { showingSession = true }
        case .reviewUnit(let unit, let dueCount):
            recommendedRow("Learn", "\(unit.title) · \(dueCount) due",
                           done: done, id: "recommended-learn") {
                recommendedLearnUnit = unit
            }
        case .unit(let unit):
            recommendedRow("Learn", "\(moduleName(unit.type)) · \(unit.title)",
                           done: done, id: "recommended-learn") {
                recommendedLearnUnit = unit
            }
        case .construction, .none:
            recommendedRow("Learn", nextConceptTitle.map { "Construction · \($0)" }
                                    ?? "Construction · review run",
                           done: done, id: "recommended-learn") {
                showingSession = true
            }
        }
    }

    private func moduleName(_ type: ConceptType) -> String {
        switch type {
        case .conjugation: "Conjugation"
        case .vocabPack: "Vocabulary"
        case .grammar: "Grammar"
        default: "Construction"
        }
    }

    private func recommendedRow(
        _ mode: String, _ title: String, done: Bool, id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                Text(mode.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 48, alignment: .leading)
                Text(title)
                    .font(DSType.body)
                    .foregroundStyle(done ? DSColor.textSecondary : DSColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// "today: 2 of 3" as a hairline (§5.5) — three quiet segments, no bar.
    private var slotHairline: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(Array(slotStates.enumerated()), id: \.offset) { _, done in
                Capsule()
                    .fill(done ? DSColor.accent : DSColor.background)
                    .frame(height: 2)
            }
        }
    }

    private var slotStates: [Bool] {
        guard let recommendation else { return [false, false, false] }
        return [recommendation.learnDone, recommendation.speakDone, recommendation.listenDone]
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
        Button { readingPassage = passage } label: {
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

        let unlocked = (try? MasteryModel.unlockedConceptIds(context: modelContext)) ?? []
        nextConceptTitle = v1
            .filter { unlocked.contains($0.id) && !$0.introduced }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }?
            .title

        recommendation = try? RecommendedPath.compose(context: modelContext)
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
