//
//  FrenchMatcherTests.swift
//  ChaisPasTests
//
//  Phase 15 acceptance (PLAN2 §7): the spoken-answer matcher is fuzzy in
//  exactly the ways spoken French varies — street reductions, ne-drop,
//  elisions — and strict everywhere else. The headline case is "chais pas"
//  grading correct for "je ne sais pas".
//

import Testing
@testable import ChaisPas

struct FrenchMatcherTests {
    // MARK: The acceptance case

    @Test func chaisPasMatchesJeNeSaisPas() {
        // The exact acceptance example: a street reduction of the negated
        // present of savoir, spoken, against the written formal target.
        #expect(FrenchMatcher.matches(
            transcript: "chais pas", targets: ["je ne sais pas"]))
        // And the intermediate ne-dropped form.
        #expect(FrenchMatcher.matches(
            transcript: "je sais pas", targets: ["je ne sais pas"]))
    }

    // MARK: Either register passes when either is the target

    @Test func formalAndStreetBothMatchEitherTarget() {
        let targets = ["tu as le temps", "t'as le temps"]
        #expect(FrenchMatcher.matches(transcript: "tu as le temps", targets: targets))
        #expect(FrenchMatcher.matches(transcript: "t'as le temps", targets: targets))
        // Even when only the formal target ships, the street rendition
        // still passes (and vice versa).
        #expect(FrenchMatcher.matches(transcript: "t'as le temps",
                                      targets: ["tu as le temps"]))
        #expect(FrenchMatcher.matches(transcript: "tu as le temps",
                                      targets: ["t'as le temps"]))
    }

    // MARK: Individual reductions

    @Test func streetReductionsExpand() {
        #expect(FrenchMatcher.matches(transcript: "chuis prêt", targets: ["je suis prêt"]))
        #expect(FrenchMatcher.matches(transcript: "j'suis prêt", targets: ["je suis prêt"]))
        #expect(FrenchMatcher.matches(transcript: "y'a personne", targets: ["il y a personne"]))
        #expect(FrenchMatcher.matches(transcript: "ya personne", targets: ["il n'y a personne"]))
        #expect(FrenchMatcher.matches(transcript: "t'es sûr", targets: ["tu es sûr"]))
    }

    // MARK: ne-drop and elision

    @Test func neDropIsSymmetric() {
        #expect(FrenchMatcher.matches(transcript: "c'est pas grave",
                                      targets: ["ce n'est pas grave"]))
        #expect(FrenchMatcher.matches(transcript: "ce n'est pas grave",
                                      targets: ["c'est pas grave"]))
    }

    @Test func elisionsAndTypographyFold() {
        // Typographic apostrophe, casing, trailing punctuation, extra spaces.
        #expect(FrenchMatcher.matches(
            transcript: "J\u{2019}ai   faim.", targets: ["j'ai faim"]))
        #expect(FrenchMatcher.matches(
            transcript: "qu'est-ce que c'est", targets: ["qu'est ce que c'est"]))
    }

    // MARK: Strictness — the "close" cases that must NOT pass

    @Test func wrongWordsDoNotMatch() {
        // A different verb is a miss, reductions notwithstanding.
        #expect(!FrenchMatcher.matches(transcript: "chais pas", targets: ["je ne peux pas"]))
        // A missing content word is a miss.
        #expect(!FrenchMatcher.matches(transcript: "je veux", targets: ["je veux un café"]))
        // Empty transcript never matches.
        #expect(!FrenchMatcher.matches(transcript: "", targets: ["je veux un café"]))
        #expect(!FrenchMatcher.matches(transcript: "   ", targets: ["c'est possible"]))
    }

    // MARK: Canonicalization is stable

    @Test func canonicalFormDropsNeAndExpandsReductions() {
        #expect(FrenchMatcher.canonicalTokens("chais pas") == ["je", "sais", "pas"])
        #expect(FrenchMatcher.canonicalTokens("je ne sais pas") == ["je", "sais", "pas"])
        #expect(FrenchMatcher.canonicalTokens("t'as") == ["tu", "as"])
        #expect(FrenchMatcher.canonicalTokens("j'ai faim") == ["je", "ai", "faim"])
    }
}
