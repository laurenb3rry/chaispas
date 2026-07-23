import SwiftData
import SwiftUI

/// Learn mode index (PLAN2 §5.1): Construction (the working v1 session),
/// then verbs, vocab packs, and grammar lessons, each opening its player.
/// Phase 16: de-carded — full-bleed hairlines, a mono data layer, mastery as a
/// quiet reading. Unmet prerequisites render as "recommended after …", never
/// locks (§8).
struct LearnIndexView: View {
    @Environment(\.modelContext) private var modelContext

    /// Sub-mode tapped on Home; scrolled to once on first appear.
    let focus: LearnSection?

    @State private var conjugation: [ConceptNode] = []
    @State private var vocabPacks: [ConceptNode] = []
    @State private var grammar: [ConceptNode] = []
    @State private var titleById: [String: String] = [:]
    @State private var scores: [String: Double] = [:]
    @State private var constructionTotal = 0
    @State private var constructionIntroduced = 0
    @State private var dueReviews = 0
    @State private var hasScrolledToFocus = false
    @State private var showingSession = false
    @State private var showingTestTables = false
    @State private var activeUnit: ConceptNode?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                        IndexHeader(title: "Learn", subtitle: "four ways into one spine")
                            .padding(.horizontal, DSSpacing.margin)
                        constructionSection
                            .id(LearnSection.construction)
                        conjugationSection
                        nodeSection(.vocabulary, title: "Vocabulary",
                                    detail: "\(vocabPacks.count) packs · \(masteredCount(vocabPacks)) mastered",
                                    nodes: vocabPacks)
                        nodeSection(.grammar, title: "Grammar",
                                    detail: "\(grammar.count) lessons · \(masteredCount(grammar)) mastered",
                                    nodes: grammar)
                    }
                    .padding(.top, DSSpacing.md)
                    .padding(.bottom, DSSpacing.xxl)
                }
                .onAppear {
                    refresh()
                    guard let focus, focus != .construction, !hasScrolledToFocus else { return }
                    hasScrolledToFocus = true
                    DispatchQueue.main.async { proxy.scrollTo(focus, anchor: .top) }
                }
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) {
            SessionView().noteCapture("Construction")
        }
        .fullScreenCover(item: $activeUnit, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) { unit in
            LearnUnitPlayerView(unit: unit)
        }
        .fullScreenCover(isPresented: $showingTestTables) {
            ConjugationTestTablesView().noteCapture("Conjugation")
        }
    }

    // MARK: Conjugation (its header carries the "test tables" entry point)

    /// Like `nodeSection`, but the detail slot on the right is a tappable
    /// "Test tables" label that opens the conjugation-table test instead of a
    /// mastery count.
    private var conjugationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Eyebrow("Conjugation")
                Spacer()
                Button { showingTestTables = true } label: {
                    Eyebrow("Test tables", color: DSColor.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("conjugation-test-tables")
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(conjugation.enumerated()), id: \.element.id) { index, node in
                nodeRow(node, title: conjugationTitle(node))
                if index < conjugation.count - 1 { Hairline() }
            }
        }
        .id(LearnSection.conjugation)
    }

    // MARK: Construction (routes to the real session)

    private var constructionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: "Construction")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            Button { showingSession = true } label: {
                HStack(spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("The sentence-building session")
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("English prompt, spoken French, native reveal.")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        MonoData(constructionDetail, color: DSColor.accent)
                            .padding(.top, DSSpacing.xs)
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
            .accessibilityIdentifier("learn-construction")
        }
    }

    private var constructionDetail: String {
        var parts = ["\(constructionTotal) concepts", "\(constructionIntroduced) introduced"]
        if dueReviews > 0 { parts.append("\(dueReviews) due") }
        return parts.joined(separator: " · ")
    }

    // MARK: Node sections (each row opens its unit's player)

    private func nodeSection(
        _ anchor: LearnSection, title: String, detail: String, nodes: [ConceptNode]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: title, detail: detail)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                nodeRow(node, title: nodeTitle(node))
                if index < nodes.count - 1 { Hairline() }
            }
        }
        .id(anchor)
    }

    /// Default row title: the concept's title as-is.
    private func nodeTitle(_ node: ConceptNode) -> Text {
        Text(node.title)
            .font(DSType.body)
            .foregroundStyle(DSColor.textPrimary)
    }

    /// Conjugation rows drop the em-dash: the verb, three spaces, then the
    /// meaning in a slightly smaller italic.
    private func conjugationTitle(_ node: ConceptNode) -> Text {
        let parts = node.title.components(separatedBy: " — ")
        guard parts.count == 2 else { return nodeTitle(node) }
        return Text(parts[0])
            .font(DSType.body)
            .foregroundStyle(DSColor.textPrimary)
            + Text("   ")
            + Text(parts[1])
                .font(.system(size: 14).italic())
                .foregroundStyle(DSColor.textSecondary)
    }

    private func nodeRow(_ node: ConceptNode, title: Text) -> some View {
        Button { activeUnit = node } label: {
            HStack(spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    title
                        .lineLimit(1)
                    if let hint = recommendationHint(node) {
                        Text(hint)
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DSSpacing.md)
                MasteryBar(fraction: scores[node.id] ?? 0)
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// Soft affordance, not a lock (§8): name the first unmet prerequisite.
    private func recommendationHint(_ node: ConceptNode) -> String? {
        guard
            let unmet = node.prereqIds.first(where: {
                (scores[$0] ?? 0) <= MasteryModel.unlockThreshold
            }),
            let title = titleById[unmet]
        else { return nil }
        return "recommended after \(title)"
    }

    private func masteredCount(_ nodes: [ConceptNode]) -> Int {
        nodes.filter { (scores[$0.id] ?? 0) >= MasteryModel.masteredThreshold }.count
    }

    // MARK: Data

    private func refresh() {
        let nodes = (try? modelContext.fetch(FetchDescriptor<ConceptNode>())) ?? []
        titleById = Dictionary(nodes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        scores = (try? MasteryModel.productionScores(context: modelContext)) ?? [:]

        let v1 = nodes.filter { SessionPlanner.v1Types.contains($0.type) }
        constructionTotal = v1.count
        constructionIntroduced = v1.filter(\.introduced).count
        conjugation = nodes.filter { $0.type == .conjugation }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
        vocabPacks = nodes.filter { $0.type == .vocabPack }
            .sorted { $0.id < $1.id }
        grammar = nodes.filter { $0.type == .grammar }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }

        let now = Date.now
        dueReviews = (try? modelContext.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.fsrsStability > 0 && $0.fsrsDue <= now }
        ))) ?? 0
    }
}

/// Routes a Learn unit to its player by concept type. Falls back to the
/// grammar layout for anything unexpected — never a dead end.
struct LearnUnitPlayerView: View {
    let unit: ConceptNode

    var body: some View {
        content.noteCapture(contextLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch unit.type {
        case .conjugation: ConjugationPlayerView(unit: unit)
        case .vocabPack: VocabPlayerView(unit: unit)
        default: GrammarPlayerView(unit: unit)
        }
    }

    private var contextLabel: String {
        switch unit.type {
        case .conjugation: "Conjugation"
        case .vocabPack: "Vocabulary"
        default: "Grammar"
        }
    }
}

#Preview {
    NavigationStack { LearnIndexView(focus: nil) }
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
