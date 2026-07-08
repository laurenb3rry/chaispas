import Foundation
import SwiftData

/// One-shot import of the bundled content pack into SwiftData.
/// Idempotent: each collection is only imported while the store has no
/// rows of it, and all inserts land in a single save, so a relaunch
/// never duplicates data.
enum ContentPackImporter {
    static func importIfNeeded(context: ModelContext) {
        do {
            try backfillTargetConceptIds(context: context)

            let conceptCount = try context.fetchCount(FetchDescriptor<ConceptNode>())
            let sentenceCount = try context.fetchCount(FetchDescriptor<Sentence>())
            guard conceptCount == 0 || sentenceCount == 0 else { return }

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
                        )
                    ))
                }
            }

            try context.save()
        } catch {
            assertionFailure("Content pack import failed: \(error)")
        }
    }

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
}
