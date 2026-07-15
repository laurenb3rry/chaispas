import SwiftData
import SwiftUI

/// Learn mode index (PLAN2 §5.1): Construction (the working v1 session),
/// then verbs, vocab packs, and grammar lessons — all browsable now, players
/// in phase 10. Rows carry live mastery hairlines; unmet prerequisites render
/// as "recommended after …" captions, never locks (§8).
struct LearnIndexView: View {
    @Environment(\.modelContext) private var modelContext

    /// Sub-mode tile tapped on Home; scrolled to once on first appear.
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
    @State private var comingSoon: ModeStub?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                        IndexHeader(title: "Learn", subtitle: "four ways into the same spine")
                        constructionCard
                            .id(LearnSection.construction)
                        nodeSection(.conjugation, title: "Conjugation",
                                    detail: "\(conjugation.count) verbs · \(masteredCount(conjugation)) mastered",
                                    nodes: conjugation, stub: .conjugation)
                        nodeSection(.vocabulary, title: "Vocabulary",
                                    detail: "\(vocabPacks.count) packs · \(masteredCount(vocabPacks)) mastered",
                                    nodes: vocabPacks, stub: .vocabulary)
                        nodeSection(.grammar, title: "Grammar",
                                    detail: "\(grammar.count) lessons · \(masteredCount(grammar)) mastered",
                                    nodes: grammar, stub: .grammar)
                    }
                    .padding(.horizontal, DSSpacing.margin)
                    .padding(.vertical, DSSpacing.xl)
                }
                .onAppear {
                    refresh()
                    guard let focus, focus != .construction, !hasScrolledToFocus else { return }
                    hasScrolledToFocus = true
                    // after layout, so the anchor rows exist
                    DispatchQueue.main.async { proxy.scrollTo(focus, anchor: .top) }
                }
            }
        }
        .toolbarBackground(DSColor.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            withAnimation(DSMotion.spring) { refresh() }
        }) {
            SessionView()
        }
        .sheet(item: $comingSoon) { ComingSoonSheet(stub: $0) }
    }

    // MARK: Construction (works today — routes to the real session)

    private var constructionCard: some View {
        Button { showingSession = true } label: {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("Construction")
                        .font(DSType.title)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                }
                Text("The sentence-building session — English prompt, spoken French, native reveal.")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.leading)
                Text(constructionDetail)
                    .font(DSType.caption.monospacedDigit())
                    .foregroundStyle(DSColor.accent)
                    .padding(.top, DSSpacing.xs)
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learn-construction")
    }

    private var constructionDetail: String {
        var parts = ["\(constructionTotal) concepts", "\(constructionIntroduced) introduced"]
        if dueReviews > 0 { parts.append("\(dueReviews) reviews due") }
        return parts.joined(separator: " · ")
    }

    // MARK: Node sections (players stubbed until phase 10)

    private func nodeSection(
        _ anchor: LearnSection, title: String, detail: String,
        nodes: [ConceptNode], stub: ModeStub
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            IndexSectionHeader(title: title, detail: detail)
            VStack(spacing: 0) {
                ForEach(nodes, id: \.id) { node in
                    nodeRow(node, stub: stub)
                    if node.id != nodes.last?.id {
                        RowDivider()
                    }
                }
            }
        }
        .id(anchor)
    }

    private func nodeRow(_ node: ConceptNode, stub: ModeStub) -> some View {
        Button { comingSoon = stub } label: {
            HStack(spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let hint = recommendationHint(node) {
                        Text(hint)
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer()
                MasteryBar(fraction: scores[node.id] ?? 0)
            }
            .padding(.vertical, DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Soft affordance, not a lock (§8): name the first prerequisite that
    /// hasn't crossed the unlock threshold yet.
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

#Preview {
    NavigationStack { LearnIndexView(focus: nil) }
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
