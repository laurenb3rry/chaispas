import Foundation
import SwiftData

/// One-shot import of the bundled content packs (v1 + v2) into SwiftData.
/// Idempotent: each collection is only imported while the store has no rows
/// of it, and all inserts land in a single save, so a relaunch never
/// duplicates data. Backfills run first so stores created by earlier phases
/// migrate in place (their new columns arrive via SwiftData lightweight
/// migration with defaults; the backfills fill in real values).
enum ContentPackImporter {
    /// Stage labels reported through the `progress` callback, in order.
    /// The UI derives its progress fraction from the index in this list.
    static let stages = [
        "Upgrading store", "Construction", "Conjugation", "Vocabulary",
        "Grammar", "Scenarios", "Episodes", "Passages", "Saving",
    ]

    /// Cheap check (fetchCounts only) for whether `importIfNeeded` would do
    /// anything — lets launch skip the loading screen on populated stores.
    /// Errs on the side of true: the import path owns error handling.
    static func needsWork(context: ModelContext) -> Bool {
        do {
            return try context.fetchCount(FetchDescriptor<ConceptNode>()) == 0
                || context.fetchCount(FetchDescriptor<Sentence>()) == 0
                || context.fetchCount(FetchDescriptor<Sentence>(
                    predicate: #Predicate { $0.packVersion == 2 })) == 0
                || context.fetchCount(FetchDescriptor<Scenario>()) == 0
                || context.fetchCount(FetchDescriptor<ListenEpisode>()) == 0
                || context.fetchCount(FetchDescriptor<Passage>()) == 0
                || context.fetchCount(FetchDescriptor<Sentence>(
                    predicate: #Predicate { $0.targetConceptId == "" })) > 0
                || context.fetchCount(FetchDescriptor<Sentence>(
                    predicate: #Predicate { $0.englishAudioRef == nil })) > 0
        } catch {
            return true
        }
    }

    static func importIfNeeded(
        context: ModelContext,
        progress: ((_ stage: String, _ index: Int) -> Void)? = nil
    ) {
        let start = Date.now
        func report(_ index: Int) { progress?(stages[index], index) }
        do {
            report(0)
            try backfillTargetConceptIds(context: context)
            try backfillEnglishAudioRefs(context: context)
            report(1)
            try importV1IfNeeded(context: context)
            try importV2IfNeeded(context: context, report: report)
            report(8)
            try context.save()
            let elapsed = Date.now.timeIntervalSince(start)
            print("[ContentPackImporter] import finished in \(String(format: "%.2f", elapsed))s")
        } catch {
            assertionFailure("Content pack import failed: \(error)")
        }
    }

    // MARK: - v1 (graph + construction sentences)

    private static func importV1IfNeeded(context: ModelContext) throws {
        let conceptCount = try context.fetchCount(FetchDescriptor<ConceptNode>())
        let sentenceCount = try context.fetchCount(FetchDescriptor<Sentence>())

        if conceptCount == 0 {
            for node in try ContentPack.loadGraph().nodes {
                guard let type = ConceptType(rawValue: node.type) else {
                    assertionFailure("Unknown concept type: \(node.type)")
                    continue
                }
                context.insert(ConceptNode(
                    id: node.id,
                    type: type,
                    tier: node.tier,
                    prereqIds: node.prereqIds,
                    title: node.title,
                    explanationText: node.explanation,
                    examples: node.canonicalExamples,
                    streetMapping: node.streetMapping
                ))
            }
        }

        if sentenceCount == 0 {
            for sentence in try ContentPack.loadSentences().sentences {
                context.insert(Sentence(
                    id: sentence.id,
                    conceptIds: sentence.conceptIds,
                    targetConceptId: sentence.targetConceptId,
                    english: sentence.english,
                    frenchFormal: sentence.frenchFormal,
                    frenchStreet: sentence.frenchStreet,
                    audioRefs: AudioRefs(
                        formal: "\(sentence.id)_formal.mp3",
                        streetSlow: "\(sentence.id)_street_slow.mp3",
                        streetFast: "\(sentence.id)_street_fast.mp3"
                    ),
                    packVersion: 1,
                    englishAudioRef: "\(sentence.id)_english.mp3"
                ))
            }
        }
    }

    // MARK: - v2 (Learn modules, Speak scenarios, Listen episodes, Read passages)

    private static func importV2IfNeeded(
        context: ModelContext, report: (Int) -> Void
    ) throws {
        try importV2LearnIfNeeded(context: context, report: report)

        report(5)
        if try context.fetchCount(FetchDescriptor<Scenario>()) == 0 {
            let encoder = JSONEncoder()
            for scenario in try ContentPackV2.loadScenarios().scenarios {
                context.insert(Scenario(
                    id: scenario.id,
                    title: scenario.title,
                    icon: scenario.icon,
                    settingBlurb: scenario.settingBlurb,
                    difficulty: scenario.difficulty,
                    variantsData: try encoder.encode(scenario.variants)
                ))
            }
        }

        report(6)
        if try context.fetchCount(FetchDescriptor<ListenEpisode>()) == 0 {
            let encoder = JSONEncoder()
            for episode in try ContentPackV2.loadEpisodes().episodes {
                context.insert(ListenEpisode(
                    id: episode.id,
                    title: episode.title,
                    level: episode.level,
                    topic: episode.topic,
                    speakerLabels: episode.speakers.map(\.label),
                    durationSec: episode.estDurationSec,
                    audioFullFast: episode.audioRefs.fullFast,
                    audioFullSlow: episode.audioRefs.fullSlow,
                    transcriptData: try encoder.encode(episode.lines),
                    questionsData: try encoder.encode(episode.questions)
                ))
            }
        }

        report(7)
        if try context.fetchCount(FetchDescriptor<Passage>()) == 0 {
            let encoder = JSONEncoder()
            for passage in try ContentPackV2.loadPassages().passages {
                context.insert(Passage(
                    id: passage.id,
                    title: passage.title,
                    style: passage.style,
                    tier: passage.tier,
                    topic: passage.topic,
                    body: passage.body,
                    wordCount: passage.wordCount,
                    glossData: try encoder.encode(passage.gloss),
                    questionsData: try encoder.encode(passage.questions)
                ))
            }
        }
    }

    /// Learn nodes and their drills import together, guarded by the drill
    /// count: they land in the same save, so either both exist or neither.
    private static func importV2LearnIfNeeded(
        context: ModelContext, report: (Int) -> Void
    ) throws {
        let v2DrillCount = try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 2 }
        ))
        guard v2DrillCount == 0 else { return }

        for (offset, module) in ContentPackV2.LearnModule.allCases.enumerated() {
            report(2 + offset)
            for node in try ContentPackV2.loadLearn(module).nodes {
                guard let type = ConceptType(rawValue: node.type) else {
                    assertionFailure("Unknown v2 concept type: \(node.type)")
                    continue
                }
                context.insert(ConceptNode(
                    id: node.id,
                    type: type,
                    tier: node.tier,
                    prereqIds: node.prereqIds,
                    title: node.title,
                    explanationText: node.explanation ?? "",
                    examples: node.canonicalExamples ?? [],
                    streetMapping: node.streetNotes ?? ""
                ))
                for drill in node.drills {
                    context.insert(Sentence(
                        id: drill.id,
                        conceptIds: drill.conceptIds,
                        targetConceptId: drill.targetConceptId,
                        english: drill.english,
                        frenchFormal: drill.frenchFormal,
                        frenchStreet: drill.frenchStreet,
                        audioRefs: AudioRefs(
                            formal: "\(drill.id)_formal.mp3",
                            streetSlow: "\(drill.id)_street_slow.mp3",
                            streetFast: "\(drill.id)_street_fast.mp3"
                        ),
                        packVersion: 2,
                        englishAudioRef: "\(drill.id)_english.mp3"
                    ))
                }
            }
        }
    }

    // MARK: - Backfills for stores created by earlier phases

    /// Stores imported before `Sentence.targetConceptId` existed migrate with
    /// the field empty; the pipeline names every sentence
    /// `<target_concept_id>_NNN`, so the value is recoverable from the id.
    private static func backfillTargetConceptIds(context: ModelContext) throws {
        let missing = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.targetConceptId == "" }
        ))
        guard !missing.isEmpty else { return }
        for sentence in missing {
            if let cut = sentence.id.lastIndex(of: "_") {
                sentence.targetConceptId = String(sentence.id[..<cut])
            }
        }
        try context.save()
    }

    /// Stores imported before `Sentence.englishAudioRef` existed migrate with
    /// nil; every drill prompt has `{id}_english.mp3` in the v2 pack.
    private static func backfillEnglishAudioRefs(context: ModelContext) throws {
        let missing = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.englishAudioRef == nil }
        ))
        guard !missing.isEmpty else { return }
        for sentence in missing {
            sentence.englishAudioRef = "\(sentence.id)_english.mp3"
        }
        try context.save()
    }
}
