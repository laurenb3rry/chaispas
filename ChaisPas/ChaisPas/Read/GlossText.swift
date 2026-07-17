import SwiftUI

/// Tokenizing and gloss lookup for the Reader's tap-a-word behavior
/// (PLAN2 §5.3). The pack's gloss maps key on surface forms — nearly a
/// sixth of them multi-word ("ce soir", "chais pas", "j'ai pris") — so a
/// tap matches the longest known phrase containing the tapped word, not
/// just the word itself.
enum GlossMatcher {
    /// Longest gloss key in the shipped pack is 4 words; a little headroom.
    static let maxPhraseWords = 5

    /// One whitespace-delimited chunk of a paragraph, rendered verbatim.
    /// `key` is its normalized lookup form — empty for tokens with no word
    /// content (standalone punctuation, emoji).
    struct Token: Identifiable, Equatable {
        let id: Int
        let text: String
        let key: String
    }

    /// A successful lookup: which tokens matched, and their English gloss.
    struct Match: Equatable {
        let range: ClosedRange<Int>
        let gloss: String
    }

    /// Lookup form: lowercased, typographic apostrophes folded, punctuation
    /// trimmed from the ends only — internal apostrophes and hyphens are
    /// word material in French (l'air, vide-grenier).
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .alphanumerics.inverted)
    }

    static func tokenize(_ paragraph: String) -> [Token] {
        paragraph.split(whereSeparator: \.isWhitespace).enumerated().map {
            Token(id: $0.offset, text: String($0.element),
                  key: normalize(String($0.element)))
        }
    }

    /// The pack's gloss map with its keys normalized the same way tokens are.
    static func normalizedGloss(_ gloss: [String: String]) -> [String: String] {
        Dictionary(
            gloss.map { key, value in
                (key.split(separator: " ").map { normalize(String($0)) }
                    .joined(separator: " "), value)
            },
            uniquingKeysWith: { a, _ in a }
        )
    }

    /// Longest phrase in the gloss containing the tapped token; windows
    /// never span tokens without word content, so phrases don't leak across
    /// punctuation. Nil when the word isn't glossed — the tap does nothing.
    static func match(
        tokens: [Token], tappedIndex: Int, gloss: [String: String]
    ) -> Match? {
        guard tokens.indices.contains(tappedIndex),
              !tokens[tappedIndex].key.isEmpty else { return nil }
        for length in stride(from: maxPhraseWords, through: 1, by: -1) {
            for start in (tappedIndex - length + 1)...tappedIndex {
                let end = start + length - 1
                guard start >= 0, end < tokens.count else { continue }
                let window = tokens[start...end]
                guard window.allSatisfy({ !$0.key.isEmpty }) else { continue }
                let phrase = window.map(\.key).joined(separator: " ")
                if let hit = gloss[phrase] {
                    return Match(range: start...end, gloss: hit)
                }
            }
        }
        return nil
    }
}

// MARK: - Flow layout

/// Greedy line-wrapping layout for the Reader's word tokens — a paragraph
/// set one word-view at a time so every word can carry a tap target.
struct FlowLayout: Layout {
    var itemSpacing: CGFloat = 4.5
    var lineSpacing: CGFloat = DSType.readerLeading

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        for (subview, position) in zip(subviews, arrange(
            proposal: proposal, subviews: subviews
        ).positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize, subviews: Subviews
    ) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.replacingUnspecifiedDimensions().width
        var positions: [CGPoint] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(origin)
            origin.x += size.width + itemSpacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, origin.x - itemSpacing)
        }
        return (positions, CGSize(width: totalWidth, height: origin.y + lineHeight))
    }
}

// MARK: - Glossed paragraph

/// Where a gloss chip is currently open: which paragraph, which match.
/// Held by the Reader so only one chip is up across the whole page.
struct ActiveGloss: Equatable {
    let paragraphId: Int
    let match: GlossMatcher.Match
}

/// The matched phrase's bounds, reported up to the Reader so it can float
/// the gloss chip over the page. Multiple anchors (a phrase wrapping across
/// lines) union at the overlay.
struct GlossAnchorKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>],
                       nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// One paragraph of tappable French. Tap a word → the longest glossed
/// phrase containing it takes a quiet background tint and reports its
/// bounds; the Reader floats the English chip over the page — the text
/// itself never reflows. Tap the chip, the phrase, an unglossed word, or
/// anywhere else → it goes away.
struct GlossTextView: View {
    let paragraphId: Int
    let tokens: [GlossMatcher.Token]
    let gloss: [String: String]
    @Binding var active: ActiveGloss?
    var font: Font = DSType.readerBody

    init(paragraphId: Int, text: String, gloss: [String: String],
         active: Binding<ActiveGloss?>, font: Font = DSType.readerBody) {
        self.paragraphId = paragraphId
        self.tokens = GlossMatcher.tokenize(text)
        self.gloss = gloss
        self._active = active
        self.font = font
    }

    private var activeMatch: GlossMatcher.Match? {
        active?.paragraphId == paragraphId ? active?.match : nil
    }

    var body: some View {
        FlowLayout(lineSpacing: DSType.readerLeading) {
            ForEach(tokens) { token in
                let matched = activeMatch?.range.contains(token.id) == true
                Text(token.text)
                    .font(font)
                    .foregroundStyle(DSColor.textPrimary)
                    // Grow the tint past the glyphs, then take the space
                    // back — the highlight breathes without moving a glyph.
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        matched ? DSColor.accent.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .padding(.horizontal, -3)
                    .padding(.vertical, -1)
                    .anchorPreference(key: GlossAnchorKey.self, value: .bounds) {
                        matched ? [$0] : []
                    }
                    .onTapGesture { tap(token) }
            }
        }
        .animation(DSMotion.spring, value: active)
    }

    private func tap(_ token: GlossMatcher.Token) {
        if let match = activeMatch, match.range.contains(token.id) {
            active = nil  // tapping the open phrase closes it
            return
        }
        if let match = GlossMatcher.match(
            tokens: tokens, tappedIndex: token.id, gloss: gloss
        ) {
            active = ActiveGloss(paragraphId: paragraphId, match: match)
        } else {
            // No gloss for this word — quietly put away whatever was open.
            active = nil
        }
    }
}

// MARK: - Floating chip

/// The gloss, floated over the page anchored to the matched phrase: above
/// it by default, below when the phrase sits too close to the top of the
/// page, clamped inside the page margins at the edges. Lives in the scroll
/// content's coordinate space, so it travels with the text and the page
/// never moves for it.
struct GlossChipOverlay: View {
    let gloss: String
    /// Union of the matched phrase's token bounds, in container space.
    let phraseRect: CGRect
    let containerSize: CGSize
    let margin: CGFloat
    let onDismiss: () -> Void

    @State private var chipSize: CGSize = .zero

    private static let gap: CGFloat = 7

    var body: some View {
        Button(action: onDismiss) {
            Text(gloss)
                .font(DSType.caption)
                .foregroundStyle(DSColor.accent)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs + 2)
                .background(DSColor.surface, in: Capsule())
                // Floating over text wants a whisper of depth (§8: soft
                // shadows, no borders).
                .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gloss-chip")
        .fixedSize()
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { chipSize = geo.size }
                    .onChange(of: geo.size) { _, size in chipSize = size }
            }
        )
        // Measured on the first pass; visible once it can be placed.
        .opacity(chipSize == .zero ? 0 : 1)
        .position(position)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private var position: CGPoint {
        let fitsAbove = phraseRect.minY - chipSize.height - Self.gap >= 0
        let y = fitsAbove
            ? phraseRect.minY - Self.gap - chipSize.height / 2
            : phraseRect.maxY + Self.gap + chipSize.height / 2
        let minX = margin + chipSize.width / 2
        let maxX = containerSize.width - margin - chipSize.width / 2
        let x = maxX < minX
            ? containerSize.width / 2  // chip wider than the column: center it
            : min(max(phraseRect.midX, minX), maxX)
        return CGPoint(x: x, y: y)
    }
}
