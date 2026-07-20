import SwiftData
import SwiftUI

/// v2 root: a scrolling library (PLAN2 §8). Phase 16: the "Recommended today"
/// widget is retired for a quiet **Continue** surface — the one or two things
/// in flight with the due-count folded in — over a de-carded, hairline library.
/// Nothing is hard-locked; order arrives as soft recommendation only.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Scenario.difficulty), SortDescriptor(\Scenario.id)])
    private var scenarios: [Scenario]
    @Query(sort: [SortDescriptor(\ListenEpisode.level), SortDescriptor(\ListenEpisode.id)])
    private var episodes: [ListenEpisode]
    @Query(sort: [SortDescriptor(\Passage.tier), SortDescriptor(\Passage.id)])
    private var passages: [Passage]

    /// Live store counts for the Learn rows.
    private struct LearnCounts {
        var constructionTotal = 0
        var constructionIntroduced = 0
        var constructionFraction = 0.0
        var verbs = 0, verbsMastered = 0, verbsFraction = 0.0
        var vocabPacks = 0, vocabMastered = 0, vocabFraction = 0.0
        var grammarLessons = 0, grammarMastered = 0, grammarFraction = 0.0
    }

    @State private var learn = LearnCounts()
    @State private var nextConceptTitle: String?
    @State private var recommendation: DailyRecommendation?
    @State private var totalDue = 0
    @State private var lastScenario: Scenario?
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
                        continueSection
                        learnSection
                        speakSection
                        readSection
                        listenSection
                    }
                    .padding(.top, DSSpacing.md)
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
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Text("Chais pas.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home-settings")
            Button { showingDebug = true } label: {
                Image(systemName: "ant")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DSSpacing.margin)
    }

    // MARK: Continue (the quiet resume surface — replaces recommended-today)

    // The 1–2 things in flight with the due-count folded into the eyebrow.
    // Degrades gracefully: no speak history → just the learn row; a bare store
    // → the learn row still points at the first unit (an invitation, not a void).
    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Continue")
                Spacer()
                if totalDue > 0 {
                    Text("\(totalDue) due")
                        .font(DSType.monoLabel).tracking(DSType.labelTracking)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(DSColor.accent)
                }
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.sm)
            Hairline()
            continueLearnRow
            if let scenario = lastScenario {
                Hairline()
                continueRow("Speak", scenario.title, "last played \(relativePlayed(scenario))",
                            id: "continue-speak") {
                    playingScenario = scenario
                }
            }
        }
    }

    @ViewBuilder
    private var continueLearnRow: some View {
        switch recommendation?.learn {
        case .review(let dueCount):
            continueRow("Learn", "Construction",
                        dueCount == 1 ? "1 review due" : "\(dueCount) reviews due",
                        id: "continue-learn") { showingSession = true }
        case .reviewUnit(let unit, let dueCount):
            continueRow("Learn", unit.title, "\(dueCount) due",
                        id: "continue-learn") { recommendedLearnUnit = unit }
        case .unit(let unit):
            continueRow("Learn", unit.title, moduleName(unit.type).lowercased(),
                        id: "continue-learn") { recommendedLearnUnit = unit }
        case .construction, .none:
            continueRow("Learn", nextConceptTitle ?? "Construction",
                        "construction", id: "continue-learn") { showingSession = true }
        }
    }

    private func continueRow(
        _ lead: String, _ title: String, _ sub: String, id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                Text(lead.uppercased())
                    .font(DSType.monoMicro).tracking(DSType.microTracking)
                    .foregroundStyle(DSColor.accent)
                    .frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(sub)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(id)
    }

    // MARK: Learn (the centerpiece — de-carded rows)

    private var learnSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Learn", detail: "4 ways in", destination: .learn(nil))
                .accessibilityIdentifier("home-section-learn")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            learnRow("Construction",
                     "\(learn.constructionTotal) concepts · \(learn.constructionIntroduced) intro",
                     fraction: learn.constructionFraction, focus: .construction)
            Hairline()
            learnRow("Conjugation",
                     "\(learn.verbs) verbs · \(learn.verbsMastered) mastered",
                     fraction: learn.verbsFraction, focus: .conjugation)
            Hairline()
            learnRow("Vocabulary",
                     "\(learn.vocabPacks) packs · \(learn.vocabMastered) mastered",
                     fraction: learn.vocabFraction, focus: .vocabulary)
            Hairline()
            learnRow("Grammar",
                     "\(learn.grammarLessons) lessons · \(learn.grammarMastered) mastered",
                     fraction: learn.grammarFraction, focus: .grammar)
        }
    }

    private func learnRow(_ name: String, _ detail: String, fraction: Double,
                          focus: LearnSection) -> some View {
        NavigationLink(value: LibraryDestination.learn(focus)) {
            HStack(spacing: DSSpacing.md) {
                Text(name)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.md)
                MonoData(detail)
                MasteryBar(fraction: fraction)
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("learn-tile-\(focus.rawValue)")
    }

    // MARK: Speak (peek — hairline rows into the index)

    private var speakSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Speak", detail: "\(scenarios.count) scenarios",
                                 destination: .speak)
                .accessibilityIdentifier("home-section-speak")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(scenarios.prefix(3).enumerated()), id: \.element.id) { index, scenario in
                Button { playingScenario = scenario } label: {
                    modeRow(icon: scenario.icon, title: scenario.title,
                            sub: scenario.settingBlurb, marker: "LVL \(scenario.difficulty)")
                }
                .buttonStyle(.pressable)
                if index < min(3, scenarios.count) - 1 { Hairline() }
            }
        }
    }

    // MARK: Read (peek)

    private var readSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Read", detail: "\(passages.count) passages",
                                 destination: .read)
                .accessibilityIdentifier("home-section-read")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(passages.prefix(3).enumerated()), id: \.element.id) { index, passage in
                Button { readingPassage = passage } label: {
                    modeRow(eyebrow: passage.style, title: passage.title,
                            marker: "TIER \(passage.tier)")
                }
                .buttonStyle(.pressable)
                if index < min(3, passages.count) - 1 { Hairline() }
            }
        }
    }

    // MARK: Listen (peek)

    private var listenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Listen", detail: "\(episodes.count) episodes",
                                 destination: .listen)
                .accessibilityIdentifier("home-section-listen")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(episodes.prefix(3).enumerated()), id: \.element.id) { index, episode in
                Button { playingEpisode = episode } label: {
                    HStack(spacing: DSSpacing.md) {
                        Text(episode.level)
                            .font(DSType.monoMicro).tracking(DSType.microTracking)
                            .foregroundStyle(DSColor.accent)
                            .frame(width: 18)
                        Text(episode.title)
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DSSpacing.md)
                        MonoData(DSFormat.duration(episode.durationSec))
                    }
                    .padding(.vertical, DSSpacing.md)
                    .padding(.horizontal, DSSpacing.margin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                if index < min(3, episodes.count) - 1 { Hairline() }
            }
        }
    }

    // A shared library row: optional leading glyph or mono eyebrow, title +
    // blurb, mono marker on the right.
    private func modeRow(icon: String? = nil, eyebrow: String? = nil,
                         title: String, sub: String? = nil, marker: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(DSColor.accent)
                    .frame(width: 20)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let eyebrow { Eyebrow(eyebrow, color: DSColor.textTertiary, micro: true) }
                Text(title)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DSSpacing.sm)
            Eyebrow(marker, color: DSColor.textTertiary, micro: true)
                .padding(.top, 2)
        }
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.margin)
        .contentShape(Rectangle())
    }

    // MARK: Data

    private func moduleName(_ type: ConceptType) -> String {
        switch type {
        case .conjugation: "Conjugation"
        case .vocabPack: "Vocabulary"
        case .grammar: "Grammar"
        default: "Construction"
        }
    }

    private func relativePlayed(_ scenario: Scenario) -> String {
        guard let last = scenario.lastPlayed else { return "not played yet" }
        return last.formatted(.relative(presentation: .named))
    }

    private func refresh() {
        let nodes = (try? modelContext.fetch(FetchDescriptor<ConceptNode>())) ?? []
        let scores = (try? MasteryModel.productionScores(context: modelContext)) ?? [:]
        func mastered(_ group: [ConceptNode]) -> Int {
            group.filter { (scores[$0.id] ?? 0) >= MasteryModel.masteredThreshold }.count
        }
        func meanFraction(_ group: [ConceptNode]) -> Double {
            guard !group.isEmpty else { return 0 }
            return group.map { scores[$0.id] ?? 0 }.reduce(0, +) / Double(group.count)
        }

        // #Predicate can't filter on the ConceptType enum — bucket in memory.
        var counts = LearnCounts()
        let v1 = nodes.filter { SessionPlanner.v1Types.contains($0.type) }
        counts.constructionTotal = v1.count
        counts.constructionIntroduced = v1.filter(\.introduced).count
        counts.constructionFraction = meanFraction(v1)
        let conjugation = nodes.filter { $0.type == .conjugation }
        counts.verbs = conjugation.count
        counts.verbsMastered = mastered(conjugation)
        counts.verbsFraction = meanFraction(conjugation)
        let vocab = nodes.filter { $0.type == .vocabPack }
        counts.vocabPacks = vocab.count
        counts.vocabMastered = mastered(vocab)
        counts.vocabFraction = meanFraction(vocab)
        let grammar = nodes.filter { $0.type == .grammar }
        counts.grammarLessons = grammar.count
        counts.grammarMastered = mastered(grammar)
        counts.grammarFraction = meanFraction(grammar)
        learn = counts

        let unlocked = (try? MasteryModel.unlockedConceptIds(context: modelContext)) ?? []
        nextConceptTitle = v1
            .filter { unlocked.contains($0.id) && !$0.introduced }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }?
            .title

        let now = Date.now
        totalDue = (try? modelContext.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.fsrsStability > 0 && $0.fsrsDue <= now }
        ))) ?? 0

        lastScenario = scenarios
            .filter { $0.lastPlayed != nil }
            .max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }

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
