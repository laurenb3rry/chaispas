import Foundation

/// Decides whether a spoken transcript counts as the target sentence
/// (PLAN.md §6, PLAN2 §7): fuzzy in exactly the ways spoken French varies —
/// street reductions, ne-drop, elisions — and strict everywhere else. Both
/// sides canonicalize into the same expanded form, so correct-but-formal and
/// correct-but-street each pass whichever register the target carries.
/// Pure and deterministic — the whole grading contract lives in unit tests.
enum FrenchMatcher {
    /// Whole-token reductions that expand to their full form. Applied after
    /// tokenization, before elision expansion.
    static let reductions: [String: [String]] = [
        "chais": ["je", "sais"],
        "chuis": ["je", "suis"],
        "ya": ["il", "y", "a"],
        "y'a": ["il", "y", "a"],
        "t'as": ["tu", "as"],
        "t'es": ["tu", "es"],
        "j'suis": ["je", "suis"],
        "j'sais": ["je", "sais"],
    ]

    /// Elided prefixes expanded to their full word. The expansion leaves
    /// "je ai"-style sequences — not French, but both sides land in the same
    /// canonical space, which is all comparison needs. `t'` maps to `tu`
    /// (object `te` collapses to the same canonical token — symmetric).
    static let elisions: [String: String] = [
        "j'": "je", "t'": "tu", "l'": "le", "d'": "de", "n'": "ne",
        "m'": "me", "s'": "se", "c'": "ce", "qu'": "que",
    ]

    /// True when the transcript's canonical form equals any target's.
    static func matches(transcript: String, targets: [String]) -> Bool {
        let heard = canonicalTokens(transcript)
        guard !heard.isEmpty else { return false }
        return targets.contains { canonicalTokens($0) == heard }
    }

    /// Lowercased, punctuation-stripped, reduction-expanded, elision-
    /// expanded, ne-dropped token sequence.
    static func canonicalTokens(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "' ")).inverted)
            .joined(separator: " ")

        var tokens: [String] = []
        for raw in cleaned.split(separator: " ") {
            // Bare apostrophes at token edges ("qu' " typed with a space).
            let token = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                .isEmpty ? "" : String(raw)
            guard !token.isEmpty else { continue }

            if let expanded = reductions[token] {
                tokens.append(contentsOf: expanded)
                continue
            }
            // Split an attached elision: "j'ai" → "je" + "ai".
            if let apostrophe = token.firstIndex(of: "'"),
               apostrophe != token.index(before: token.endIndex) {
                let prefix = String(token[...apostrophe])
                let rest = String(token[token.index(after: apostrophe)...])
                if let full = elisions[prefix] {
                    // The rest may itself be a reduction ("t'as" handled
                    // above; nested elisions don't occur).
                    tokens.append(full)
                    tokens.append(rest)
                    continue
                }
            }
            // A trailing elision typed as its own token: "j'" → "je".
            if let full = elisions[token] {
                tokens.append(full)
                continue
            }
            tokens.append(token)
        }

        // Ne-drop tolerance: spoken French drops "ne"; comparison ignores it
        // on both sides ("je ne sais pas" ≡ "je sais pas" ≡ "chais pas").
        return tokens.filter { $0 != "ne" }
    }
}
