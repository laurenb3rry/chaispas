import Foundation
import SwiftData

/// What the placement assessment concluded (PLAN2 §6): mastery priors per
/// concept × axis plus the two starting points the modes read off them.
struct PlacementResult: Equatable {
    /// v1-tier-scale (0–3) comprehension priors from the staircase.
    var comprehensionPriorByTier: [Int: Double]
    /// v1-tier-scale production priors from elicited production.
    var productionPriorByTier: [Int: Double]
    /// Per-sampled-verb production priors (conjugation node ids).
    var conjugationPriors: [String: Double]
    /// Per-vocab-pack priors from the yes/no module (comprehension scale;
    /// production is seeded at a discount — recognition isn't recall).
    var vocabPackPriors: [String: Double]
    var listenLevel: String
    var readTier: Int
    /// Rough known-word count for the summary screen.
    var vocabEstimate: Int
}

/// Pure scoring for the three placement modules, and the seeding of their
/// output into MasteryScore rows. Kept engine-free so tests can drive it
/// with scripted answers.
enum PlacementScoring {
    struct StaircaseAnswer: Equatable {
        var tier: Int
        var correct: Bool
    }

    struct ProductionAnswer: Equatable {
        /// v1 tier the prompt sampled, nil when it sampled a verb.
        var tier: Int?
        /// Conjugation node id when the prompt sampled a verb.
        var verbConceptId: String?
        var correct: Bool
    }

    struct VocabAnswer: Equatable {
        /// Frequency band (0 = most frequent) for real words; nil for
        /// pseudo-words.
        var band: Int?
        var isWord: Bool
        var saidWord: Bool
    }

    // Priors sit deliberately below `MasteryModel.masteredThreshold`: a
    // clean tier pass clears the unlock threshold (0.6) so the scheduler
    // fast-forwards, but nothing is ever *mastered* by assessment alone.
    // 0.75 also aligns the composer's mastery-derived Listen level with the
    // staircase's rung-based one: a perfect staircase means priors at
    // exactly the level-D boundary.
    static let cleanPrior = 0.75
    static let partialPrior = 0.45
    static let attemptedPrior = 0.15
    static let verbPrior = 0.65
    /// Recognition (yes/no) seeds production at a discount.
    static let vocabProductionDiscount = 0.75

    // MARK: Scoring

    static func result(
        staircase: [StaircaseAnswer],
        highestRungPassed: Int,
        production: [ProductionAnswer],
        vocab: [VocabAnswer],
        vocabPackIdsByBand: [Int: [String]]
    ) -> PlacementResult {
        // Guess-corrected vocab acceptance: hit rate per band minus the
        // overall false-alarm rate on pseudo-words (LexTALE's correction).
        let pseudo = vocab.filter { !$0.isWord }
        let falseAlarmRate = pseudo.isEmpty
            ? 0 : Double(pseudo.count(where: \.saidWord)) / Double(pseudo.count)
        var vocabPackPriors: [String: Double] = [:]
        var vocabEstimate = 0.0
        let bands = Set(vocab.compactMap(\.band))
        for band in bands {
            let real = vocab.filter { $0.band == band }
            guard !real.isEmpty else { continue }
            let hitRate = Double(real.count(where: \.saidWord)) / Double(real.count)
            let corrected = max(0, hitRate - falseAlarmRate)
            // Each band spans 8 packs × 25 words.
            vocabEstimate += corrected * 200
            let prior: Double? = corrected >= 0.7 ? 0.6 : corrected >= 0.4 ? 0.35 : nil
            if let prior {
                for packId in vocabPackIdsByBand[band] ?? [] {
                    vocabPackPriors[packId] = prior
                }
            }
        }

        return PlacementResult(
            comprehensionPriorByTier: tierPriors(
                staircase.map { (tier: $0.tier, correct: $0.correct) }),
            productionPriorByTier: tierPriors(
                production.compactMap { answer in
                    answer.tier.map { (tier: $0, correct: answer.correct) }
                }),
            conjugationPriors: Dictionary(
                production.compactMap { answer in
                    answer.correct ? answer.verbConceptId.map { ($0, verbPrior) } : nil
                },
                uniquingKeysWith: { a, _ in a }
            ),
            vocabPackPriors: vocabPackPriors,
            listenLevel: listenLevel(highestRungPassed: highestRungPassed),
            readTier: staircase.filter(\.correct).map(\.tier).max() ?? 0,
            vocabEstimate: Int((vocabEstimate / 50).rounded()) * 50
        )
    }

    /// Per-tier prior from that tier's answers: clean → 0.7 (clears the
    /// unlock threshold), mixed → 0.45, attempted-and-missed → 0.15 (the
    /// attempt itself is weak evidence of exposure). Unattempted tiers get
    /// no prior at all.
    static func tierPriors(_ answers: [(tier: Int, correct: Bool)]) -> [Int: Double] {
        Dictionary(grouping: answers, by: \.tier).mapValues { group in
            let correct = group.count(where: \.correct)
            return correct == group.count ? cleanPrior
                : correct > 0 ? partialPrior : attemptedPrior
        }
    }

    /// The staircase has two rungs per tier (slower register, then faster);
    /// the highest rung survived maps straight onto the four Listen levels.
    static func listenLevel(highestRungPassed: Int) -> String {
        switch highestRungPassed {
        case ..<2: "A"
        case ..<4: "B"
        case ..<6: "C"
        default: "D"
        }
    }

    // MARK: Seeding

    /// Writes the priors as MasteryScore rows, max-merged: placement can
    /// reveal knowledge the store hasn't seen, never erase evidence it has.
    /// Tier priors apply to the v1 spine and to grammar lessons (both share
    /// the 0–3 tier scale); conjugation and vocab nodes get their module's
    /// own priors.
    static func seed(_ result: PlacementResult, context: ModelContext, now: Date = .now) throws {
        let existing = try context.fetch(FetchDescriptor<MasteryScore>())
        var byKey = Dictionary(
            existing.map { ("\($0.conceptId)|\($0.axis.rawValue)", $0) },
            uniquingKeysWith: { a, _ in a }
        )

        func raise(_ conceptId: String, _ axis: DrillAxis, to prior: Double) {
            let key = "\(conceptId)|\(axis.rawValue)"
            if let score = byKey[key] {
                guard prior > score.score else { return }
                score.score = prior
                score.updatedAt = now
            } else {
                let score = MasteryScore(conceptId: conceptId, axis: axis,
                                         score: prior, updatedAt: now)
                context.insert(score)
                byKey[key] = score
            }
        }

        for node in try context.fetch(FetchDescriptor<ConceptNode>())
        where SessionPlanner.v1Types.contains(node.type) || node.type == .grammar {
            if let prior = result.comprehensionPriorByTier[node.tier] {
                raise(node.id, .comprehension, to: prior)
            }
            if let prior = result.productionPriorByTier[node.tier] {
                raise(node.id, .production, to: prior)
            }
        }
        for (conceptId, prior) in result.conjugationPriors {
            raise(conceptId, .production, to: prior)
            raise(conceptId, .comprehension, to: prior)
        }
        for (packId, prior) in result.vocabPackPriors {
            raise(packId, .comprehension, to: prior)
            raise(packId, .production, to: prior * vocabProductionDiscount)
        }

        try context.save()
    }
}

/// First-launch offer gate plus the last-run summary (UserDefaults-backed;
/// suppressible in UI tests via `-placementOffered YES` launch arguments,
/// which land in the defaults argument domain).
enum PlacementGate {
    static let offeredKey = "placementOffered"

    /// Offer on first launch only: never re-offer once seen, and never
    /// interrupt a store that already carries real drill history.
    static func shouldOffer(context: ModelContext) -> Bool {
        // UI-test hook (argument domain): force the offer regardless of
        // store state — test classes share a clone's store, so "fresh
        // install" can't be assumed mid-suite.
        if UserDefaults.standard.bool(forKey: "placementForceOffer") { return true }
        guard !UserDefaults.standard.bool(forKey: offeredKey) else { return false }
        return ((try? context.fetchCount(FetchDescriptor<DrillEvent>())) ?? 1) == 0
    }

    static func markOffered() {
        UserDefaults.standard.set(true, forKey: offeredKey)
    }

    static func recordCompletion(_ result: PlacementResult, now: Date = .now) {
        let defaults = UserDefaults.standard
        defaults.set(now.timeIntervalSince1970, forKey: "placement.completedAt")
        defaults.set(result.listenLevel, forKey: "placement.listenLevel")
        defaults.set(result.readTier, forKey: "placement.readTier")
        defaults.set(result.vocabEstimate, forKey: "placement.vocabEstimate")
    }

    struct Summary {
        var completedAt: Date
        var listenLevel: String
        var readTier: Int
        var vocabEstimate: Int
    }

    static var lastSummary: Summary? {
        let defaults = UserDefaults.standard
        let interval = defaults.double(forKey: "placement.completedAt")
        guard interval > 0, let level = defaults.string(forKey: "placement.listenLevel")
        else { return nil }
        return Summary(
            completedAt: Date(timeIntervalSince1970: interval),
            listenLevel: level,
            readTier: defaults.integer(forKey: "placement.readTier"),
            vocabEstimate: defaults.integer(forKey: "placement.vocabEstimate")
        )
    }
}
