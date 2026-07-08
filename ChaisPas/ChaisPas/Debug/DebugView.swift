import AVFoundation
import SwiftData
import SwiftUI

/// Temporary phase-3 verification screen: shows what the importer loaded,
/// the FSRS queue state, and plays a sample audio file straight from the
/// bundled content pack.
struct DebugView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var conceptCount = 0
    @State private var sentenceCount = 0
    @State private var newCount = 0
    @State private var dueReviewCount = 0
    @State private var unlockedCount = 0
    @State private var sample: Sentence?
    @State private var status = ""
    @State private var player: AVAudioPlayer?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    Text("Debug — Phase 3")
                        .font(DSType.largeTitle)
                        .tracking(DSType.largeTitleTracking)
                        .foregroundStyle(DSColor.textPrimary)

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        statRow("Concepts loaded", conceptCount)
                        statRow("Sentences loaded", sentenceCount)
                        statRow("New (never drilled)", newCount)
                        statRow("Reviews due now", dueReviewCount)
                        statRow("Concepts unlocked", unlockedCount)
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))

                    if let sample {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            Text(sample.english)
                                .font(DSType.englishPrompt)
                                .foregroundStyle(DSColor.textSecondary)
                            Text(sample.frenchFormal)
                                .font(DSType.french)
                                .foregroundStyle(DSColor.textPrimary)
                            Text(sample.frenchStreet)
                                .font(DSType.french)
                                .foregroundStyle(DSColor.accent)
                            HStack(spacing: DSSpacing.md) {
                                playButton("Formal", file: sample.audioRefs.formal)
                                playButton("Street slow", file: sample.audioRefs.streetSlow)
                                playButton("Street fast", file: sample.audioRefs.streetFast)
                            }
                        }
                        .padding(DSSpacing.lg)
                        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.vertical, DSSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .task { refresh() }
        .refreshable { refresh() }
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .font(DSType.body)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
            Text("\(value)")
                .font(DSType.body.monospacedDigit())
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    private func playButton(_ label: String, file: String) -> some View {
        Button(label) { play(file) }
            .font(DSType.caption)
            .foregroundStyle(DSColor.background)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(DSColor.accent, in: Capsule())
    }

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

            var descriptor = FetchDescriptor<Sentence>(sortBy: [SortDescriptor(\.id)])
            descriptor.fetchLimit = 1
            sample = try modelContext.fetch(descriptor).first
        } catch {
            status = "Refresh failed: \(error.localizedDescription)"
        }
    }

    private func play(_ fileName: String) {
        guard let url = ContentPack.audioURL(fileName: fileName) else {
            status = "Audio not found in bundle: \(fileName)"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            status = "Playing \(fileName)"
        } catch {
            status = "Playback failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DebugView()
        .modelContainer(for: [ConceptNode.self, Sentence.self, DrillEvent.self, MasteryScore.self, SessionLog.self], inMemory: true)
}
