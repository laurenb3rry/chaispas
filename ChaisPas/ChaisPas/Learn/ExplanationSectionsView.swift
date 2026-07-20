import SwiftUI

/// Renders a structured explanation (phase 10b): ordered sections of
/// header + body, optional bullets, optional french/english example pairs.
/// The Read-reader typography standard applies — this is set like a page,
/// not a card: DSType hierarchy, generous line spacing, hairline-separated
/// sections.
struct ExplanationSectionsView: View {
    let sections: [ContentPackV2.ExplanationSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Eyebrow(section.header, color: DSColor.accent)

                    Text(section.body)
                        .font(DSType.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineSpacing(4)

                    if let bullets = section.bullets, !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.xs + 2) {
                            ForEach(bullets, id: \.self) { bullet in
                                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                                    Circle()
                                        .fill(DSColor.textSecondary)
                                        .frame(width: 3, height: 3)
                                        .offset(y: -3)
                                    Text(bullet)
                                        .font(DSType.body)
                                        .foregroundStyle(DSColor.textPrimary)
                                        .lineSpacing(3)
                                }
                            }
                        }
                        .padding(.top, DSSpacing.xs)
                    }

                    if let examples = section.examples, !examples.isEmpty {
                        // reading-scale pairs, set quiet — no border chrome
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            ForEach(examples, id: \.self) { pair in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pair.french)
                                        .font(DSType.frenchCompact)
                                        .foregroundStyle(DSColor.textPrimary)
                                    Text(pair.english)
                                        .font(DSType.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                            }
                        }
                        .padding(.top, DSSpacing.xs)
                    }
                }
                .padding(.vertical, DSSpacing.lg)
                if index < sections.count - 1 {
                    RowDivider()
                }
            }
        }
    }
}

/// "When to use this tense" panel under the conjugation table (phase 10b):
/// the shared usage note plus side-by-side contrast pairs.
struct TenseUsageView: View {
    let usage: ContentPackV2.TenseUsage

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Eyebrow("When to use it", color: DSColor.accent)
                Text(usage.note)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineSpacing(4)
            }

            ForEach(Array(usage.contrasts.enumerated()), id: \.offset) { _, contrast in
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    // Two columns split by a hairline — de-carded contrast.
                    HStack(alignment: .top, spacing: DSSpacing.md) {
                        contrastCell(french: contrast.aFrench, english: contrast.aEnglish)
                        Rectangle().fill(DSColor.hairline).frame(width: 1)
                        contrastCell(french: contrast.bFrench, english: contrast.bEnglish)
                    }
                    Text(contrast.point)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }

    private func contrastCell(french: String, english: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(french)
                .font(DSType.frenchCompact)
                .foregroundStyle(DSColor.textPrimary)
            Text(english)
                .font(DSType.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, DSSpacing.xs)
    }
}
