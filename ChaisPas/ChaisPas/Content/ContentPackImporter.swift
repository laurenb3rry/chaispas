import Foundation
import SwiftData

/// One-shot import of the bundled content pack into SwiftData.
/// Idempotent: each collection is only imported while the store has no
/// rows of it, and all inserts land in a single save, so a relaunch
/// never duplicates data.
enum ContentPackImporter {
    static func importIfNeeded(context: ModelContext) {
        do {
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
}
