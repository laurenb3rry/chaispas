import Foundation
import SwiftData

/// The Home card's daily composition (PLAN2 §5.5): one Learn unit, one Speak
/// scenario, one Listen episode. Purely a suggestion — the slot flags report
/// whether today's DrillEvents already cover each slot, wherever the work
/// happened; completing anything anywhere counts.
struct DailyRecommendation {
    enum LearnPick {
        /// Overdue Construction reviews exist → the session (its warm recall
        /// drains the due queue first).
        case review(dueCount: Int)
        /// Only v2 Learn drills are overdue → the unit holding the most of
        /// them (a drill run surfaces due items first).
        case reviewUnit(ConceptNode, dueCount: Int)
        /// Nothing due → the next new unit, gap-weighted round-robin.
        case unit(ConceptNode)
        /// No v2 unit to suggest (bare store) — fall back to Construction.
        case construction
    }

    var learn: LearnPick
    var speak: Scenario?
    var listen: ListenEpisode?
    var learnDone: Bool
    var speakDone: Bool
    var listenDone: Bool

    var doneCount: Int { [learnDone, speakDone, listenDone].count(where: { $0 }) }
}

/// Assembles the recommendation from the FSRS queue and the mastery model.
/// Everything derives from the store — placement priors, drill history, and
/// scenario/episode progress all move the picks with no state of its own.
enum RecommendedPath {
    /// The v2 Learn modules the round-robin rotates through, in tiebreak order.
    static let learnModules: [ConceptType] = [.conjugation, .grammar, .vocabPack]

    static func compose(context: ModelContext, now: Date = .now) throws -> DailyRecommendation {
        let nodes = try context.fetch(FetchDescriptor<ConceptNode>())
        let production = try MasteryModel.scores(axis: .production, context: context)
        let comprehension = try MasteryModel.scores(axis: .comprehension, context: context)
        let v1Nodes = nodes.filter { SessionPlanner.v1Types.contains($0.type) }

        let scenarios = try context.fetch(FetchDescriptor<Scenario>())
        let episodes = try context.fetch(FetchDescriptor<ListenEpisode>())

        // Today's slots — any event in the mode's family covers its slot.
        let startOfDay = Calendar.current.startOfDay(for: now)
        let today = try context.fetch(FetchDescriptor<DrillEvent>(
            predicate: #Predicate { $0.timestamp >= startOfDay }
        ))
        let speakDone = today.contains { $0.sentenceId.hasPrefix("scn_") }
        let listenDone = today.contains { $0.sentenceId.hasPrefix("lst_") }
        let learnDone = today.contains {
            !$0.sentenceId.hasPrefix("scn_") && !$0.sentenceId.hasPrefix("lst_")
                && !$0.sentenceId.hasPrefix("rd_")
        }

        return DailyRecommendation(
            learn: try learnPick(nodes: nodes, production: production, context: context, now: now),
            speak: speakPick(scenarios: scenarios, level: meanScore(of: v1Nodes, in: production)),
            listen: listenPick(episodes: episodes,
                               level: listenLevel(comprehension: meanScore(of: v1Nodes,
                                                                           in: comprehension))),
            learnDone: learnDone,
            speakDone: speakDone,
            listenDone: listenDone
        )
    }

    // MARK: Learn (§5.5 priority: overdue reviews → review session; else
    // next unit, round-robin weighted by mastery gaps)

    private static func learnPick(
        nodes: [ConceptNode], production: [String: Double],
        context: ModelContext, now: Date
    ) throws -> DailyRecommendation.LearnPick {
        // Due Construction sentences → the session, whose warm recall is the
        // review vehicle.
        let dueV1 = try context.fetchCount(FetchDescriptor<Sentence>(
            predicate: #Predicate {
                $0.packVersion == 1 && $0.fsrsStability > 0 && $0.fsrsDue <= now
            }
        ))
        if dueV1 > 0 { return .review(dueCount: dueV1) }

        // Due v2 Learn drills → the unit holding the most of them. Scenario
        // lines and mode questions also live in pack 2 but aren't
        // learn-drillable (the phase-11 dilution lesson) — excluded.
        let dueV2 = try context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate {
                $0.packVersion == 2 && $0.fsrsStability > 0 && $0.fsrsDue <= now
                    && !$0.id.starts(with: "scn_") && !$0.id.starts(with: "lst_")
                    && !$0.id.starts(with: "rd_")
            }
        ))
        if !dueV2.isEmpty {
            let nodeById: [String: ConceptNode] = Dictionary(
                nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
            )
            let dueByTarget: [String: Int] = Dictionary(grouping: dueV2, by: \.targetConceptId)
                .mapValues(\.count)
            var candidates: [(node: ConceptNode, due: Int)] = []
            for (targetId, due) in dueByTarget {
                if let node = nodeById[targetId] {
                    candidates.append((node, due))
                }
            }
            candidates.sort { $0.due != $1.due ? $0.due > $1.due : $0.node.id < $1.node.id }
            if let unit = candidates.first {
                return .reviewUnit(unit.node, dueCount: unit.due)
            }
        }

        if let unit = nextUnit(nodes: nodes, production: production) {
            return .unit(unit)
        }
        return .construction
    }

    /// Weighted round-robin over conjugation/grammar/vocab: every touched
    /// unit advances its module's clock by 1/gap, so a module with a bigger
    /// mastery gap runs a slower clock and gets more turns — and priors that
    /// close a module's gap (placement) visibly push the pick elsewhere.
    /// Exposed for the placement acceptance test.
    static func nextUnit(nodes: [ConceptNode], production: [String: Double]) -> ConceptNode? {
        var best: (unit: ConceptNode, clock: Double)?
        for type in learnModules {
            let units = nodes.filter { $0.type == type }
                .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
            let remaining = units.filter {
                (production[$0.id] ?? 0) < MasteryModel.masteredThreshold
            }
            guard !remaining.isEmpty else { continue }

            let gap = 1 - meanScore(of: units, in: production)
            let touched = Double(units.count(where: { (production[$0.id] ?? 0) > 0 }))
            let clock = touched / max(gap, 0.05)

            // Prefer a unit whose prerequisites are met — a soft preference,
            // never a lock (§8).
            let unit = remaining.first {
                MasteryModel.isUnlocked($0, productionScores: production)
            } ?? remaining[0]
            if best == nil || clock < best!.clock {
                best = (unit, clock)
            }
        }
        return best?.unit
    }

    // MARK: Speak (least-completed, difficulty-appropriate)

    /// `level` is mean v1 production mastery in [0, 1]; scenario difficulty
    /// runs 1–3 in the pack.
    static func speakPick(scenarios: [Scenario], level: Double) -> Scenario? {
        guard let fewest = scenarios.map(\.completedCount).min() else { return nil }
        let target = targetDifficulty(level: level)
        return scenarios.filter { $0.completedCount == fewest }
            .min {
                (abs($0.difficulty - target), $0.difficulty, $0.id)
                    < (abs($1.difficulty - target), $1.difficulty, $1.id)
            }
    }

    static func targetDifficulty(level: Double) -> Int {
        level < 0.25 ? 1 : level < 0.55 ? 2 : 3
    }

    // MARK: Listen (level from comprehension mastery)

    /// `comprehension` is mean v1 comprehension mastery in [0, 1].
    static func listenLevel(comprehension: Double) -> String {
        switch comprehension {
        case ..<0.25: "A"
        case ..<0.5: "B"
        case ..<0.75: "C"
        default: "D"
        }
    }

    static func listenPick(episodes: [ListenEpisode], level: String) -> ListenEpisode? {
        // At the level if it has episodes, else the nearest level below
        // (never overshoot a thin level upward).
        let ranks = ["A": 0, "B": 1, "C": 2, "D": 3]
        let want = ranks[level] ?? 0
        let candidates = episodes
            .filter { (ranks[$0.level] ?? 0) <= want }
            .max { a, b in (ranks[a.level] ?? 0) < (ranks[b.level] ?? 0) }
            .map { top in episodes.filter { $0.level == top.level } }
            ?? episodes
        return candidates.min {
            ($0.completedCount, $0.id) < ($1.completedCount, $1.id)
        }
    }

    // MARK: Helpers

    /// Mean mastery over a node group; unscored concepts count as 0, an
    /// empty group as 0.
    static func meanScore(of nodes: [ConceptNode], in scores: [String: Double]) -> Double {
        guard !nodes.isEmpty else { return 0 }
        return nodes.map { scores[$0.id] ?? 0 }.reduce(0, +) / Double(nodes.count)
    }
}
