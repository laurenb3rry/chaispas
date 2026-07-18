import Foundation

/// Colours what the user said against the target line(s) so they can grade
/// themselves at a glance: a spoken word that lands in the target is
/// "correct" (green), anything else white — and if nothing landed, the whole
/// utterance reads red. Pure and deterministic; the view only renders it.
enum SpokenComparison {
    struct Word: Equatable {
        var text: String
        var correct: Bool
    }

    struct Result: Equatable {
        var words: [Word]
        /// No spoken word matched — the view paints the whole line red.
        var noneCorrect: Bool
    }

    /// A spoken word is correct when all of its canonical tokens (street
    /// reductions expanded, ne dropped — via `FrenchMatcher`) appear
    /// somewhere in the union of the targets. Comparing against both the
    /// street and formal renditions means either register counts.
    static func compare(spoken: String, targets: [String]) -> Result {
        let targetTokens = Set(targets.flatMap { FrenchMatcher.canonicalTokens($0) })
        let words = spoken
            .split(separator: " ")
            .map(String.init)
            .map { display -> Word in
                let canon = FrenchMatcher.canonicalTokens(display)
                let correct = !canon.isEmpty && canon.allSatisfy { targetTokens.contains($0) }
                return Word(text: display, correct: correct)
            }
        return Result(words: words, noneCorrect: !words.contains { $0.correct })
    }
}
