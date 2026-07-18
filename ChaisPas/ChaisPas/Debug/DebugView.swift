import AVFoundation
import SwiftData
import SwiftUI

/// Temporary verification screen: shows what the importer loaded (store
/// counts side-by-side with the pack v2 manifest), the FSRS queue state, and
/// plays sample audio from every pack module.
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

    /// (label, store count, manifest count) rows for the v2 inventory card.
    @State private var v2Rows: [(String, Int, Int)] = []
    @State private var speakSampleFile: String?
    @State private var listenSampleFile: String?
    @State private var englishSampleFile: String?
    /// Result of the last v2 audio action, shown inside the audio card so
    /// failures are never below the fold. nil = nothing attempted yet.
    @State private var audioStatus: (message: String, failed: Bool)?

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Developer")
                            .font(DSType.caption.weight(.medium))
                            .tracking(1.2)
                            .foregroundStyle(DSColor.textSecondary)
                        Text("Debug")
                            .font(DSType.largeTitle)
                            .tracking(DSType.largeTitleTracking)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("Internal build inspector — store vs. pack manifest and audio checks. Not part of the app's flow.")
                            .font(DSType.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        statRow("Concepts loaded", "\(conceptCount)")
                        statRow("Sentences loaded", "\(sentenceCount)")
                        statRow("New (never drilled)", "\(newCount)")
                        statRow("Reviews due now", "\(dueReviewCount)")
                        statRow("Concepts unlocked", "\(unlockedCount)")
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        HStack {
                            Text("Pack v2 inventory")
                                .font(DSType.body)
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text("store / manifest")
                                .font(DSType.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        ForEach(v2Rows, id: \.0) { row in
                            statRow(row.0, "\(row.1) / \(row.2)",
                                    ok: row.1 == row.2)
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text("Pack v2 audio")
                            .font(DSType.body)
                            .foregroundStyle(DSColor.textPrimary)
                        HStack(spacing: DSSpacing.md) {
                            v2AudioButton("Speak", file: speakSampleFile, module: .speak)
                            v2AudioButton("Listen", file: listenSampleFile, module: .listen)
                            v2AudioButton("English", file: englishSampleFile, module: .englishPrompts)
                        }
                        // Always-visible result line: errors surface here, in
                        // the card, not in the status text at the page bottom
                        Text(audioStatus?.message ?? "Tap a button — the result shows here.")
                            .font(DSType.caption)
                            .foregroundStyle(audioStatus == nil ? DSColor.textSecondary
                                             : audioStatus!.failed ? DSColor.gradeFailure
                                             : DSColor.accent)
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
                                playButton("Formal") { playV1(sample.audioRefs.formal) }
                                playButton("Street slow") { playV1(sample.audioRefs.streetSlow) }
                                playButton("Street fast") { playV1(sample.audioRefs.streetFast) }
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

    private func statRow(_ label: String, _ value: String, ok: Bool = true) -> some View {
        HStack {
            Text(label)
                .font(DSType.body)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
            Text(value)
                .font(DSType.body.monospacedDigit())
                .foregroundStyle(ok ? DSColor.textPrimary : DSColor.gradeFailure)
        }
    }

    private func playButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(DSType.caption)
            .foregroundStyle(DSColor.background)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(DSColor.accent, in: Capsule())
    }

    /// Renders even when the sample file couldn't be derived, so a payload
    /// or fetch failure is a visible disabled button, not a missing one.
    private func v2AudioButton(
        _ label: String, file: String?, module: ContentPackV2.AudioModule
    ) -> some View {
        Button(label) {
            if let file {
                playV2(file, module: module)
            }
        }
        .font(DSType.caption)
        .foregroundStyle(file == nil ? DSColor.textSecondary : DSColor.background)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(file == nil ? DSColor.background : DSColor.accent, in: Capsule())
        .disabled(file == nil)
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

            try refreshV2()
        } catch {
            status = "Refresh failed: \(error.localizedDescription)"
        }
    }

    private func refreshV2() throws {
        let manifest = try ContentPackV2.loadManifest().content

        // Concept nodes and drills bucketed per Learn module. #Predicate
        // can't filter on the ConceptType enum — bucket in memory (66 nodes).
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

        // One sample file per new audio module, derived from the imported
        // models so the buttons also exercise the payload decode path.
        // Derivation failures land in the audio card, never silently nil.
        do {
            var scenarios = FetchDescriptor<Scenario>(sortBy: [SortDescriptor(\.id)])
            scenarios.fetchLimit = 1
            guard let scenario = try modelContext.fetch(scenarios).first else {
                throw CocoaError(.coreData, userInfo: [
                    NSLocalizedDescriptionKey: "no Scenario rows in store"])
            }
            let node = try scenario.decodedVariants().first?.nodes.first
            speakSampleFile = node?.audioRefs?["street_fast"]
            if speakSampleFile == nil {
                audioStatus = ("Speak: first node of \(scenario.id) has no street_fast ref", true)
            }
        } catch {
            speakSampleFile = nil
            audioStatus = ("Speak sample failed: \(error.localizedDescription)", true)
        }

        var episodes = FetchDescriptor<ListenEpisode>(sortBy: [SortDescriptor(\.id)])
        episodes.fetchLimit = 1
        listenSampleFile = try modelContext.fetch(episodes).first?.audioFullFast
        if listenSampleFile == nil {
            audioStatus = ("Listen: no ListenEpisode rows in store", true)
        }

        englishSampleFile = sample?.englishAudioRef
        if englishSampleFile == nil {
            audioStatus = ("English: first sentence has no englishAudioRef", true)
        }
    }

    private func playV1(_ fileName: String) {
        play(url: ContentPack.audioURL(fileName: fileName), fileName: fileName) {
            status = $0
        }
    }

    private func playV2(_ fileName: String, module: ContentPackV2.AudioModule) {
        play(url: ContentPackV2.audioURL(fileName: fileName, module: module),
             fileName: "\(module.rawValue)/\(fileName)") {
            audioStatus = ($0, !$0.hasPrefix("Playing"))
        }
    }

    /// Plays off the main thread: the first AVAudioPlayer in a freshly
    /// booted simulator initializes CoreAudio, which can block for tens of
    /// seconds — the phase-8 "buttons do nothing" bug. The sink receives an
    /// immediate "Loading…" then the outcome; both also print to the console
    /// so failures show up in Xcode even if the UI is missed.
    private func play(url: URL?, fileName: String,
                      sink: @escaping (String) -> Void) {
        guard let url else {
            let message = "Audio not found in bundle: \(fileName)"
            print("[DebugView audio] \(message)")
            sink(message)
            return
        }
        sink("Loading \(fileName)… (first play after simulator boot can take a while)")
        Task.detached(priority: .userInitiated) {
            var message: String
            var p: AVAudioPlayer?
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                let created = try AVAudioPlayer(contentsOf: url)
                created.prepareToPlay()
                if created.play() {
                    message = "Playing \(fileName) (\(String(format: "%.1f", created.duration))s)"
                } else {
                    message = "AVAudioPlayer.play() returned false for \(fileName)"
                }
                p = created
            } catch {
                message = "Playback failed for \(fileName): \(error.localizedDescription)"
            }
            print("[DebugView audio] \(message)")
            let outcome = message
            let created = p
            await MainActor.run {
                player = created  // retain so playback isn't deallocated mid-sound
                sink(outcome)
            }
        }
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
