import Foundation
import SwiftData

/// Section 2.2 mastery model: sentences are the SRS unit (FSRS); concept
/// mastery is derived from performance on sentences containing the concept,
/// via a latency-weighted exponential moving average per (concept, axis).
enum MasteryModel {
    static let learningRate = 0.2
    /// Prereqs must exceed this production mastery for a concept to unlock.
    static let unlockThreshold = 0.6

    /// Latency weighting: full credit at or under this latency…
    static let fastLatencyMs = 2_000
    /// …decaying linearly to `slowCredit` at or beyond this latency.
    static let slowLatencyMs = 8_000
    static let slowCredit = 0.5

    /// Latency thresholds for mapping drill results to FSRS grades.
    static let fsrsHardLatencyMs = 6_000

    /// Evidence value in [0,1] for one drill response: 0 when incorrect;
    /// when correct, 1.0 fast shading down to `slowCredit` slow.
    static func evidenceValue(correct: Bool, latencyMs: Int) -> Double {
        guard correct else { return 0 }
        if latencyMs <= fastLatencyMs { return 1 }
        if latencyMs >= slowLatencyMs { return slowCredit }
        let t = Double(latencyMs - fastLatencyMs) / Double(slowLatencyMs - fastLatencyMs)
        return 1 - t * (1 - slowCredit)
    }

    /// Conservative auto-mapping: no `.easy` — easy inflates early intervals,
    /// and a drill response carries less signal than a deliberate self-grade.
    static func fsrsGrade(correct: Bool, latencyMs: Int) -> FSRS.Grade {
        guard correct else { return .again }
        return latencyMs >= fsrsHardLatencyMs ? .hard : .good
    }

    /// Records one drill response: persists the DrillEvent, updates the FSRS
    /// state of the sentence, and EMA-updates the mastery score of every
    /// concept the sentence used.
    static func recordDrill(
        sentence: Sentence,
        axis: DrillAxis,
        correct: Bool,
        latencyMs: Int,
        pronunciationScore: Double? = nil,
        now: Date = .now,
        context: ModelContext
    ) throws {
        context.insert(DrillEvent(
            sentenceId: sentence.id,
            axis: axis,
            correct: correct,
            latencyMs: latencyMs,
            pronunciationScore: pronunciationScore,
            timestamp: now
        ))

        FSRS.review(sentence, grade: fsrsGrade(correct: correct, latencyMs: latencyMs), now: now)

        let target = evidenceValue(correct: correct, latencyMs: latencyMs)
        for conceptId in sentence.conceptIds {
            let score = try fetchOrCreateScore(conceptId: conceptId, axis: axis, context: context)
            score.score += learningRate * (target - score.score)
            score.updatedAt = now
        }

        try context.save()
    }

    /// A concept is unlocked when every prerequisite exceeds the production
    /// threshold. Per-axis-aware by design: unlocking keys off production
    /// only, so comprehension is free to run ahead.
    static func isUnlocked(_ node: ConceptNode, productionScores: [String: Double]) -> Bool {
        node.prereqIds.allSatisfy { (productionScores[$0] ?? 0) > unlockThreshold }
    }

    /// IDs of all currently unlocked concepts.
    static func unlockedConceptIds(context: ModelContext) throws -> Set<String> {
        let nodes = try context.fetch(FetchDescriptor<ConceptNode>())
        let scores = try productionScores(context: context)
        return Set(nodes.filter { isUnlocked($0, productionScores: scores) }.map(\.id))
    }

    /// conceptId → production mastery.
    static func productionScores(context: ModelContext) throws -> [String: Double] {
        let all = try context.fetch(FetchDescriptor<MasteryScore>())
        return Dictionary(
            all.filter { $0.axis == .production }.map { ($0.conceptId, $0.score) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    private static func fetchOrCreateScore(
        conceptId: String, axis: DrillAxis, context: ModelContext
    ) throws -> MasteryScore {
        // Predicate on the string field only: SwiftData cannot filter on
        // Codable enum properties, so the (tiny) axis filter happens in memory
        let descriptor = FetchDescriptor<MasteryScore>(
            predicate: #Predicate { $0.conceptId == conceptId }
        )
        if let existing = try context.fetch(descriptor).first(where: { $0.axis == axis }) {
            return existing
        }
        let score = MasteryScore(conceptId: conceptId, axis: axis)
        context.insert(score)
        return score
    }
}
