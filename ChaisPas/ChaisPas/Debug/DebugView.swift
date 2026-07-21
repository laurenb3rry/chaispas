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
            try refreshV2()
        } catch {
            status = "Refresh failed: \(error.localizedDescription)"
        }
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
