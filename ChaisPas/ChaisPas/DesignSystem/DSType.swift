import SwiftUI

/// Phase 16 type system — an instrument, not a poster. Two faces: SF Pro for
/// content (French hero, prompts, titles) and SF Mono for the data layer
/// (labels, counts, tiers, metadata). Hierarchy comes from colour, position
/// and weight far more than size — so the scale is small and tight. Tracking
/// is tight on large sizes (negative) and loose on the small mono caps.
enum DSType {
    // MARK: Sans — content

    /// Screen titles ("Chais pas.", "Speak", "Et voilà.") — body-adjacent,
    /// Benji-restraint, not a hero.
    static let largeTitle = Font.system(size: 25, weight: .bold)
    static let largeTitleTracking: CGFloat = -0.4

    static let title = Font.system(size: 19, weight: .semibold)
    static let body = Font.system(size: 16)
    /// Secondary sans (blurbs, subtitles) — a step under body.
    static let caption = Font.system(size: 14)

    /// Scenario NPC lines — the French holds the stage while it plays.
    static let french = Font.system(size: 20, weight: .medium)
    /// English prompt once the French has taken the stage (recedes).
    static let englishPrompt = Font.system(size: 15)

    // MARK: Player stage
    /// English cue while listening — prominent, holds the stage.
    static let stagePrompt = Font.system(size: 20, weight: .regular)
    /// The French reveal — the hero, but composed not cartoonish.
    static let stageFrench = Font.system(size: 28, weight: .medium)
    /// Street form under the hero, at reading scale.
    static let stageFrenchSecondary = Font.system(size: 19, weight: .medium)

    /// Inline example pairs / canonical-example lines.
    static let frenchCompact = Font.system(size: 16, weight: .medium)
    /// Conjugation-table cells.
    static let tableForm = Font.system(size: 16, weight: .medium)
    /// Oversized numeral (due counts) — restrained from its old 64.
    static let statNumeral = Font.system(size: 44, weight: .semibold)

    // MARK: Reader — a set page keeps a touch more size + leading.
    static let readerTitle = Font.system(size: 22, weight: .semibold)
    static let readerBody = Font.system(size: 18)
    static let readerLeading: CGFloat = 8

    // MARK: Mono — the data layer

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Section eyebrows / labels (uppercased at the call site, `labelTracking`).
    static let monoLabel = mono(11, .medium)
    /// Counts, durations, metadata.
    static let monoData = mono(12)
    /// Tier / level / phase markers (uppercased, `microTracking`).
    static let monoMicro = mono(10, .medium)

    static let labelTracking: CGFloat = 1.4
    static let microTracking: CGFloat = 1.6
    static let dataTracking: CGFloat = 0.2
}
