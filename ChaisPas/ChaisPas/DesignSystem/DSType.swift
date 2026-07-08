import SwiftUI

/// SF Pro with optical sizing (the system font switches to SF Pro Display
/// automatically at >=20pt). French text renders larger than English
/// prompts — the French is the star.
enum DSType {
    static let largeTitle = Font.system(size: 34, weight: .bold)
    /// Tight tracking for large-title moments; apply via .tracking()
    static let largeTitleTracking: CGFloat = -0.8

    static let title = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 17)
    static let caption = Font.system(size: 13)

    static let french = Font.system(size: 24, weight: .medium)
    static let englishPrompt = Font.system(size: 17)

    /// Session center stage: the French reveal outsizes the English prompt.
    static let stagePrompt = Font.system(size: 24, weight: .regular)
    static let stageFrench = Font.system(size: 31, weight: .medium)
    static let stageFrenchSecondary = Font.system(size: 21, weight: .medium)
    /// Oversized numeral for the Today screen's due count.
    static let statNumeral = Font.system(size: 64, weight: .semibold)
}
