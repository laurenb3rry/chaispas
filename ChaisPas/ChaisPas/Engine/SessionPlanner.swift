import Foundation
import SwiftData

/// What a session will work through, assembled up front from the FSRS queue
/// and the mastery model (PLAN.md section 2.3). The ladder and spontaneous
/// lists are candidate pools — the engine consumes them adaptively at runtime.
struct SessionPlan {
    /// Due SRS items, most overdue first (phase 1: warm recall).
    var warmRecall: [Sentence]
    /// The node to introduce today; nil when everything unlocked is already
    /// introduced (the ladder then reviews the weakest introduced concept).
    var newConcept: ConceptNode?
    /// Concept the construction ladder drills (newConcept.id, or the fallback).
    var targetConceptId: String
    /// Human title for the target, for the summary screen.
    var targetConceptTitle: String
    /// All drills targeting the concept, sorted easiest → hardest.
    var ladderPool: [Sentence]
    /// Candidates mixing the target with older concepts (phase 5 pool).
    var spontaneousPool: [Sentence]

    var isEmpty: Bool { warmRecall.isEmpty && ladderPool.isEmpty }
}

enum SessionPlanner {
    static let warmRecallCount = 3

    /// Difficulty proxy for ordering the construction ladder: how many
    /// concepts the sentence combines, then how long it is. Matches the
    /// pipeline's 2-word-combo → full-sentence progression well enough
    /// that the ~70% controller only has to make local adjustments.
    static func difficulty(_ s: Sentence) -> (Int, Int) {
        (s.conceptIds.count, s.frenchFormal.split(separator: " ").count)
    }

    /// The concept types the v1 Construction session drills. Pack v2 adds
    /// conjugation/vocab_pack/grammar nodes (several with no prereqs, so
    /// instantly unlocked), but their drills live in the v2 pack and belong
    /// to the Learn players — keep them out of this session until phase 10
    /// rehomes Construction under Learn.
    static let v1Types: Set<ConceptType> = [
        .construction, .chunk, .vocabCluster, .register, .constructionRegister,
    ]

    static func makePlan(context: ModelContext, now: Date = .now) throws -> SessionPlan {
        let nodes = try context.fetch(FetchDescriptor<ConceptNode>())
            .filter { v1Types.contains($0.type) }
        let unlocked = try MasteryModel.unlockedConceptIds(context: context)
        let introduced = Set(nodes.filter(\.introduced).map(\.id))

        // Today's new node: lowest tier first among unlocked-but-not-introduced.
        let newConcept = nodes
            .filter { unlocked.contains($0.id) && !$0.introduced }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }

        // No new material left at this mastery level → review ladder on the
        // weakest introduced concept instead of introducing nothing.
        let target: ConceptNode?
        if let newConcept {
            target = newConcept
        } else {
            let production = try MasteryModel.productionScores(context: context)
            target = nodes
                .filter { $0.introduced }
                .min { (production[$0.id] ?? 0, $0.id) < (production[$1.id] ?? 0, $1.id) }
        }
        let targetId = target?.id ?? ""

        // Warm recall: most overdue reviews first, nothing new.
        var dueDescriptor = FetchDescriptor<Sentence>(
            predicate: #Predicate {
                $0.packVersion == 1 && $0.fsrsStability > 0 && $0.fsrsDue <= now
            },
            sortBy: [SortDescriptor(\.fsrsDue)]
        )
        dueDescriptor.fetchLimit = warmRecallCount
        let warmRecall = try context.fetch(dueDescriptor)

        // The core rule: a drill may only use concepts already introduced
        // (plus today's target). The pipeline validator enforces this at
        // generation time; re-checking here keeps the scheduler honest too.
        let allowed = introduced.union([targetId])
        let ladderPool = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 && $0.targetConceptId == targetId }
        ))
        .filter { Set($0.conceptIds).isSubset(of: allowed) }
        .sorted {
            let (a, b) = (difficulty($0), difficulty($1))
            return (a.0, a.1, $0.id) < (b.0, b.1, $1.id)
        }

        // Spontaneous close: sentences combining the target with older
        // concepts, unseen and richer combinations first.
        let spontaneousPool = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 && $0.targetConceptId != targetId }
        ))
        .filter {
            $0.conceptIds.contains(targetId)
                && $0.conceptIds.count >= 2
                && Set($0.conceptIds).isSubset(of: allowed)
        }
        .sorted {
            let (a, b) = ($0.fsrsStability <= 0 ? 0 : 1, $1.fsrsStability <= 0 ? 0 : 1)
            return (a, -$0.conceptIds.count, $0.id) < (b, -$1.conceptIds.count, $1.id)
        }

        return SessionPlan(
            warmRecall: warmRecall,
            newConcept: newConcept,
            targetConceptId: targetId,
            targetConceptTitle: target?.title ?? "",
            ladderPool: ladderPool,
            spontaneousPool: spontaneousPool
        )
    }
}
