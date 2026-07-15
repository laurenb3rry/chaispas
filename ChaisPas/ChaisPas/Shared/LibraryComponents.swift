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

/// Home section header: tracked-caps title + count detail + chevron, the
/// whole row a NavigationLink into the mode's index.
struct LibrarySectionHeader: View {
    let title: String
    let detail: String
    let destination: LibraryDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Text(title.uppercased())
                    .font(DSType.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(DSColor.textPrimary)
                Text(detail)
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An index screen's large-title moment (the system nav bar stays chrome-less,
/// contributing only the back chevron).
struct IndexHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSType.largeTitle)
                .tracking(DSType.largeTitleTracking)
                .foregroundStyle(DSColor.textPrimary)
            Text(subtitle)
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
    }
}

/// Sub-section header inside an index screen (no navigation).
struct IndexSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text(title.uppercased())
                .font(DSType.caption.weight(.medium))
                .tracking(1.2)
                .foregroundStyle(DSColor.textPrimary)
            Text(detail)
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
        }
    }
}

/// Production mastery as a quiet 40×2 hairline — an instrument reading,
/// not a progress bar.
struct MasteryBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(DSColor.surface)
            Capsule().fill(DSColor.accent)
                .frame(width: 40 * max(0, min(1, fraction)))
        }
        .frame(width: 40, height: 2)
    }
}

/// Keeps scrolled content legible under the status bar on screens without a
/// navigation bar (Home): a background-colored fade over the top safe area.
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

/// Thin separator between rows in a list group.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DSColor.textSecondary.opacity(0.12))
            .frame(height: 0.5)
    }
}

enum DSFormat {
    /// 34 → "0:34", 92 → "1:32"
    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
