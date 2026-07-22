import Foundation
import SwiftData

/// Deterministic RNG (SplitMix64) so placement runs are seedable in tests
/// while staying varied across real runs.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Samples the placement assessment's items from the shipped packs. Split
/// out of `PlacementEngine` so the engine coordinates the run while this
/// owns construction — the pure-logic sibling of `PlacementScoring`. All
/// content comes from the packs; only the pseudo-word list is authored.
@MainActor
enum PlacementItems {
    /// Everything a fresh assessment needs, sampled once at engine init.
    struct Built {
        var staircase: [PlacementEngine.StaircaseItem]
        var production: [PlacementEngine.ProductionItem]
        var vocab: [PlacementEngine.VocabItem]
        var vocabPackIdsByBand: [Int: [String]]
    }

    static func build(context: ModelContext, seed: UInt64) -> Built {
        var rng = SeededRNG(seed: seed)
        let nodes = (try? context.fetch(FetchDescriptor<ConceptNode>())) ?? []
        let v1Tiers = Dictionary(
            nodes.filter { SessionPlanner.v1Types.contains($0.type) }.map { ($0.id, $0.tier) },
            uniquingKeysWith: { a, _ in a }
        )
        let v1Sentences = (try? context.fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.packVersion == 1 }
        ))) ?? []
        let byTier = Dictionary(grouping: v1Sentences) { v1Tiers[$0.targetConceptId] ?? -1 }

        var vocabPackIdsByBand: [Int: [String]] = [:]
        return Built(
            staircase: staircase(byTier: byTier, rng: &rng),
            production: production(byTier: byTier, nodes: nodes, context: context, rng: &rng),
            vocab: vocab(packIdsByBand: &vocabPackIdsByBand, rng: &rng),
            vocabPackIdsByBand: vocabPackIdsByBand
        )
    }

    // MARK: Module 1 — comprehension staircase

    private static func staircase(
        byTier: [Int: [Sentence]], rng: inout SeededRNG
    ) -> [PlacementEngine.StaircaseItem] {
        var items: [PlacementEngine.StaircaseItem] = []
        var usedIds = Set<String>()
        for rung in PlacementEngine.rungs {
            let pool = (byTier[rung.tier] ?? []).filter { !usedIds.contains($0.id) }
            guard let sentence = pool.randomElement(using: &rng) else { continue }
            usedIds.insert(sentence.id)

            // The transcription target is whatever register the audio
            // actually speaks.
            let (audioFile, answer) = switch rung.register {
            case .formal: (sentence.audioRefs.formal, sentence.frenchFormal)
            case .streetSlow: (sentence.audioRefs.streetSlow, sentence.frenchStreet)
            case .streetFast: (sentence.audioRefs.streetFast, sentence.frenchStreet)
            }
            items.append(PlacementEngine.StaircaseItem(
                tier: rung.tier,
                register: rung.register,
                audioFile: audioFile,
                answer: answer
            ))
        }
        return items
    }

    // MARK: Module 2 — elicited production

    private static func production(
        byTier: [Int: [Sentence]], nodes: [ConceptNode],
        context: ModelContext, rng: inout SeededRNG
    ) -> [PlacementEngine.ProductionItem] {
        // Two prompts per v1 tier plus one verb after each of the first
        // three tiers: t0 t0 v · t1 t1 v · t2 t2 v · t3 t3 — 11 items.
        var items: [PlacementEngine.ProductionItem] = []
        var usedIds = Set<String>()
        func tierItem(_ tier: Int) -> PlacementEngine.ProductionItem? {
            var pool = (byTier[tier] ?? []).filter { !usedIds.contains($0.id) }
            // Middle-difficulty slice: skip the trivial openers and the
            // hardest combinations — one prompt has to stand for the tier.
            pool.sort {
                $0.frenchFormal.split(separator: " ").count
                    < $1.frenchFormal.split(separator: " ").count
            }
            if pool.count >= 8 {
                pool = Array(pool[(pool.count / 4)..<(pool.count * 3 / 4)])
            }
            guard let sentence = pool.randomElement(using: &rng) else { return nil }
            usedIds.insert(sentence.id)
            return PlacementEngine.ProductionItem(sentence: sentence, tier: tier, verbConceptId: nil)
        }

        let verbs = nodes.filter { $0.type == .conjugation }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
            .prefix(3)
        var verbItems: [PlacementEngine.ProductionItem] = verbs.compactMap { verb in
            let verbId = verb.id
            let drills = (try? context.fetch(FetchDescriptor<Sentence>(
                predicate: #Predicate { $0.targetConceptId == verbId }
            ))) ?? []
            return drills.randomElement(using: &rng).map {
                PlacementEngine.ProductionItem(sentence: $0, tier: nil, verbConceptId: verbId)
            }
        }

        for tier in 0...3 {
            items.append(contentsOf: [tierItem(tier), tierItem(tier)].compactMap { $0 })
            if !verbItems.isEmpty, tier < 3 {
                items.append(verbItems.removeFirst())
            }
        }
        return items
    }

    // MARK: Module 3 — vocab yes/no

    private static func vocab(
        packIdsByBand: inout [Int: [String]], rng: inout SeededRNG
    ) -> [PlacementEngine.VocabItem] {
        // Real words sampled across the frequency ranks: the 40 packs fold
        // into 5 bands of 8, four words each.
        let packs = ((try? ContentPackV2.loadLearn(.vocab))?.nodes ?? [])
            .sorted { $0.id < $1.id }
        var real: [PlacementEngine.VocabItem] = []
        for band in 0..<PlacementEngine.bandCount {
            let bandPacks = packs.dropFirst(band * 8).prefix(8)
            guard !bandPacks.isEmpty else { continue }
            packIdsByBand[band] = bandPacks.map(\.id)
            let lemmas = bandPacks.flatMap { $0.words ?? [] }
                .map(\.lemma)
                .filter { !$0.contains(" ") }  // pseudo-words are single tokens
            real.append(contentsOf: lemmas.shuffled(using: &rng)
                .prefix(PlacementEngine.realWordsPerBand)
                .map { PlacementEngine.VocabItem(text: $0, band: band, isWord: true) })
        }
        guard !real.isEmpty else { return [] }
        let pseudo = PlacementEngine.pseudoWords.map {
            PlacementEngine.VocabItem(text: $0, band: nil, isWord: false)
        }
        return (real + pseudo).shuffled(using: &rng)
    }
}
