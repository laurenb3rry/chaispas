import SwiftUI

/// Where the Home library can navigate.
enum LibraryDestination: Hashable {
    case learn(LearnSection?)
    case speak
    case read
    case listen
}

/// Learn's four sub-modes; also the scroll anchors on the Learn index.
enum LearnSection: String, Hashable {
    case construction, conjugation, vocabulary, grammar
}

// MARK: - Data-layer primitives (the phase-16 signature)

/// Mono uppercased eyebrow / section label — sans is for content, mono for
/// what the instrument reports. Tracking loosens on these small caps.
struct Eyebrow: View {
    let text: String
    var color: Color = DSColor.textSecondary
    var micro = false

    init(_ text: String, color: Color = DSColor.textSecondary, micro: Bool = false) {
        self.text = text; self.color = color; self.micro = micro
    }

    var body: some View {
        Text(text.uppercased())
            .font(micro ? DSType.monoMicro : DSType.monoLabel)
            .tracking(micro ? DSType.microTracking : DSType.labelTracking)
            .foregroundStyle(color)
    }
}

/// Mono metadata (counts, durations) — tabular, recessive by default.
struct MonoData: View {
    let text: String
    var color: Color = DSColor.textTertiary

    init(_ text: String, color: Color = DSColor.textTertiary) {
        self.text = text; self.color = color
    }

    var body: some View {
        Text(text)
            .font(DSType.monoData).tracking(DSType.dataTracking)
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

/// The primary structural device — a thin rule between rows.
struct Hairline: View {
    var strong = false
    var body: some View {
        Rectangle()
            .fill(strong ? DSColor.hairlineStrong : DSColor.hairline)
            .frame(height: 1)
    }
}

/// Kept name for existing call sites — now a plain hairline.
struct RowDivider: View {
    var body: some View { Hairline() }
}

// MARK: - Section headers

/// Home section header: mono eyebrow + faint mono detail + chevron, the whole
/// row a NavigationLink into the mode's index. Pair it with a `Hairline`.
struct LibrarySectionHeader: View {
    let title: String
    let detail: String
    let destination: LibraryDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Eyebrow(title)
                Spacer()
                Eyebrow(detail, color: DSColor.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An index screen's title moment: restrained sans title + mono caption.
struct IndexHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title)
                .font(DSType.largeTitle)
                .tracking(DSType.largeTitleTracking)
                .foregroundStyle(DSColor.textPrimary)
            Eyebrow(subtitle)
        }
    }
}

/// Sub-section header inside an index screen (no navigation). Pair with a
/// `Hairline(strong: true)`.
struct IndexSectionHeader: View {
    let title: String
    var detail: String? = nil

    // Existing call sites pass (title:detail:); keep that shape.
    init(title: String, detail: String = "") {
        self.title = title
        self.detail = detail.isEmpty ? nil : detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Eyebrow(title)
            if let detail {
                Eyebrow(detail, color: DSColor.textTertiary)
            }
            Spacer()
        }
    }
}

/// Production mastery as a quiet 36×2 hairline — an instrument reading, not a
/// progress bar.
struct MasteryBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(DSColor.surface)
            Capsule().fill(DSColor.accent)
                .frame(width: 36 * max(0, min(1, fraction)))
        }
        .frame(width: 36, height: 2)
    }
}

/// Keeps scrolled content legible under the status bar on chrome-less screens.
struct StatusBarScrim: View {
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [DSColor.background, DSColor.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: geo.safeAreaInsets.top + 12)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

enum DSFormat {
    /// 34 → "0:34", 92 → "1:32"
    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
