import SwiftData
import SwiftUI

/// Internal build inspector: what the importer loaded (store counts) and the
/// pack v2 inventory (store vs. manifest). Not part of the app's flow — reached
/// from the ant icon on Home.
struct DebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var conceptCount = 0
    @State private var sentenceCount = 0
    @State private var newCount = 0
    @State private var dueReviewCount = 0
    @State private var unlockedCount = 0
    @State private var status = ""

    /// (label, store count, manifest count) rows for the v2 inventory.
    @State private var v2Rows: [(String, Int, Int)] = []

    /// (title, production mastery, introduced, unlocked) for the v1 Construction
    /// concepts, tier order — the ladder the SessionPlanner walks. Lets you
    /// watch production mastery climb toward the 0.6 unlock gate rep by rep.
    @State private var masteryRows: [(String, Double, Bool, Bool)] = []

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    header

                    section("Store") {
                        statRow("Concepts loaded", "\(conceptCount)")
                        statRow("Sentences loaded", "\(sentenceCount)")
                        statRow("New (never drilled)", "\(newCount)")
                        statRow("Reviews due now", "\(dueReviewCount)")
                        statRow("Concepts unlocked", "\(unlockedCount)")
                    }

                    section("Construction mastery", detail: "production · 0.6 unlocks") {
                        ForEach(masteryRows, id: \.0) { row in
                            masteryRow(row.0, row.1, introduced: row.2, unlocked: row.3)
                        }
                    }

                    section("Pack v2 inventory", detail: "store / manifest") {
                        ForEach(v2Rows, id: \.0) { row in
                            statRow(row.0, "\(row.1) / \(row.2)", ok: row.1 == row.2)
                        }
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.gradeFailure)
                            .padding(.horizontal, DSSpacing.margin)
                    }
                }
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .task { refresh() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Eyebrow("Developer")
                Text("Debug")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("debug-close")
        }
        .padding(.horizontal, DSSpacing.margin)
    }

    private func section<Content: View>(
        _ title: String, detail: String? = nil, @ViewBuilder rows: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IndexSectionHeader(title: title, detail: detail ?? "")
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.sm)
            Hairline(strong: true)
            rows()
        }
    }

    private func statRow(_ label: String, _ value: String, ok: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text(value)
                    .font(DSType.monoData)
                    .monospacedDigit()
                    .foregroundStyle(ok ? DSColor.textTertiary : DSColor.gradeFailure)
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            Hairline()
        }
    }

    /// One Construction concept: production mastery vs. the unlock gate, with
    /// its introduced/unlocked state. Value tints red until it clears 0.6.
    private func masteryRow(
        _ title: String, _ production: Double, introduced: Bool, unlocked: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text([introduced ? "introduced" : "not introduced",
                          unlocked ? "unlocked" : "locked"].joined(separator: " · "))
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                Spacer()
                Text(String(format: "%.2f", production))
                    .font(DSType.monoData)
                    .monospacedDigit()
                    .foregroundStyle(
                        production > MasteryModel.unlockThreshold
                            ? DSColor.textTertiary : DSColor.gradeFailure
                    )
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.margin)
            Hairline()
        }
    }

    // MARK: Data

    private func refresh() {
        do {
            conceptCount = try modelContext.fetchCount(FetchDescriptor<ConceptNode>())
            sentenceCount = try modelContext.fetchCount(FetchDescriptor<Sentence>())
            newCount = try modelContext.fetchCount(FetchDescriptor<Sentence>(
                predicate: #Predicate { $0.fsrsStability <= 0 }
            ))
            let now = Date.now
            dueReviewCount = try modelContext.fetchCount(FetchDescriptor<Sentence>(
                predicate: #Predicate { $0.fsrsStability > 0 && $0.fsrsDue <= now }
            ))
            unlockedCount = try MasteryModel.unlockedConceptIds(context: modelContext).count
            try refreshMastery()
            try refreshV2()
        } catch {
            status = "Refresh failed: \(error.localizedDescription)"
        }
    }

    /// The v1 Construction concepts in the order the planner introduces them
    /// (tier, then id), with production mastery, introduced flag, and whether
    /// prereqs currently clear the unlock gate.
    private func refreshMastery() throws {
        let production = try MasteryModel.productionScores(context: modelContext)
        let unlocked = try MasteryModel.unlockedConceptIds(context: modelContext)
        masteryRows = try modelContext.fetch(FetchDescriptor<ConceptNode>())
            .filter { SessionPlanner.v1Types.contains($0.type) }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
            .map { ($0.title, production[$0.id] ?? 0, $0.introduced, unlocked.contains($0.id)) }
    }

    private func refreshV2() throws {
        let manifest = try ContentPackV2.loadManifest().content

        // #Predicate can't filter on the ConceptType enum — bucket in memory.
        let concepts = try modelContext.fetch(FetchDescriptor<ConceptNode>())
        let typeById = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0.type) })
        let nodeCounts = Dictionary(grouping: concepts, by: \.type).mapValues(\.count)

        let v2Drills = try modelContext.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 2 }
        ))
        let drillCounts = Dictionary(grouping: v2Drills) { typeById[$0.targetConceptId] }
            .mapValues(\.count)

        let scenarioCount = try modelContext.fetchCount(FetchDescriptor<Scenario>())
        let episodeCount = try modelContext.fetchCount(FetchDescriptor<ListenEpisode>())
        let passageCount = try modelContext.fetchCount(FetchDescriptor<Passage>())

        v2Rows = [
            ("Conjugation nodes", nodeCounts[.conjugation] ?? 0, manifest.learn.conjugation.nodes),
            ("Conjugation drills", drillCounts[.conjugation] ?? 0, manifest.learn.conjugation.drills),
            ("Vocab packs", nodeCounts[.vocabPack] ?? 0, manifest.learn.vocab.nodes),
            ("Vocab drills", drillCounts[.vocabPack] ?? 0, manifest.learn.vocab.drills),
            ("Grammar lessons", nodeCounts[.grammar] ?? 0, manifest.learn.grammar.nodes),
            ("Grammar drills", drillCounts[.grammar] ?? 0, manifest.learn.grammar.drills),
            ("Speak scenarios", scenarioCount, manifest.speak.scenarios),
            ("Listen episodes", episodeCount, manifest.listen.episodes),
            ("Read passages", passageCount, manifest.read.passages),
        ]
    }
}

#Preview {
    DebugView()
        .modelContainer(
            for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self,
                  SessionLog.self, Scenario.self, ListenEpisode.self, Passage.self],
            inMemory: true
        )
}
