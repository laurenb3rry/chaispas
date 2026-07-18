//
//  SpokenComparisonTests.swift
//  ChaisPasTests
//
//  Phase 15 (§7, revised): the reveal colours what the user said against the
//  target — green where a word landed, white where it didn't, and the whole
//  line red when nothing landed. Street reductions still count (via the
//  FrenchMatcher canonicalisation), so "chais" scores against "je sais".
//

import Testing
@testable import ChaisPas

struct SpokenComparisonTests {
    @Test func correctWordsAreGreenExtrasAreWhite() {
        let result = SpokenComparison.compare(
            spoken: "je veux un thé",
            targets: ["je veux un café"]
        )
        #expect(result.words == [
            .init(text: "je", correct: true),
            .init(text: "veux", correct: true),
            .init(text: "un", correct: true),
            .init(text: "thé", correct: false),   // wrong noun → white
        ])
        #expect(!result.noneCorrect)
    }

    @Test func streetReductionsCountAsCorrect() {
        // "chais pas" against the formal "je ne sais pas": every spoken word
        // canonicalises into the target, so both are green.
        let result = SpokenComparison.compare(
            spoken: "chais pas",
            targets: ["je ne sais pas"]
        )
        #expect(result.words.allSatisfy { $0.correct })
        #expect(!result.noneCorrect)
    }

    @Test func eitherRegisterCounts() {
        // The street rendition scores against the pair of targets even when
        // the formal is primary.
        let result = SpokenComparison.compare(
            spoken: "t'as le temps",
            targets: ["tu as le temps", "t'as le temps"]
        )
        #expect(result.words.allSatisfy { $0.correct })
    }

    @Test func nothingRightFlagsTheWholeLine() {
        let result = SpokenComparison.compare(
            spoken: "bonjour comment ça va",
            targets: ["je veux un café"]
        )
        #expect(result.words.allSatisfy { !$0.correct })
        #expect(result.noneCorrect)
    }

    @Test func emptyTranscriptIsNoneCorrect() {
        let result = SpokenComparison.compare(spoken: "", targets: ["c'est possible"])
        #expect(result.words.isEmpty)
        #expect(result.noneCorrect)
    }
}
