import SwiftUI

/// Shows what speech recognition heard (PLAN2 §7, revised). While the user is
/// still speaking it's plain grey ("still listening"); at the reveal it's
/// coloured against the target so a glance tells them how they did — green
/// for words that landed, white for the rest, the whole line red if nothing
/// landed. It is a mirror for the user's own grade, never a grade itself.
struct SpokenTranscriptView: View {
    let spoken: String
    /// nil while still listening (plain grey); the target renditions once
    /// revealed (then the text is coloured).
    let targets: [String]?

    var body: some View {
        if let targets {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Eyebrow("You said", micro: true)
                colored(SpokenComparison.compare(spoken: spoken, targets: targets))
                    .font(DSType.frenchCompact)
            }
        } else {
            Text(spoken)
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
                .italic()
        }
    }

    @ViewBuilder
    private func colored(_ result: SpokenComparison.Result) -> some View {
        if result.noneCorrect {
            Text(result.words.map(\.text).joined(separator: " "))
                .foregroundStyle(DSColor.gradeFailure)
        } else {
            Text(attributed(result))
        }
    }

    /// Per-word colours as one wrapping run: green where correct, white
    /// otherwise.
    private func attributed(_ result: SpokenComparison.Result) -> AttributedString {
        var line = AttributedString()
        for (index, word) in result.words.enumerated() {
            if index > 0 { line += AttributedString(" ") }
            var piece = AttributedString(word.text)
            piece.foregroundColor = word.correct ? DSColor.gradeSuccess : DSColor.textPrimary
            line += piece
        }
        return line
    }
}
