import SwiftData
import SwiftUI

/// The Reader (PLAN2 §5.3) — the typography showcase: a cleanly set page,
/// style and tier worn lightly at the top, French body at reading scale
/// with room to breathe. Tap any word for its gloss; the questions wait at
/// the end of the page like end-of-chapter exercises, and the done state
/// is one quiet line.
struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let passage: Passage

    /// Wider than the app margin: a text column, not an app screen.
    private static let pageMargin: CGFloat = 28

    @State private var engine: ReadEngine?
    @State private var activeGloss: ActiveGloss?
    @State private var gloss: [String: String] = [:]

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let engine {
                content(engine)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard engine == nil else { return }
            gloss = GlossMatcher.normalizedGloss((try? passage.decodedGloss()) ?? [:])
            engine = ReadEngine(passage: passage, context: modelContext)
        }
    }

    private func content(_ engine: ReadEngine) -> some View {
        VStack(spacing: 0) {
            chrome
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PullToDismissDetector { dismiss() }.frame(height: 0)
                    header
                        .padding(.bottom, DSSpacing.xxl)
                    passageBody
                    questionSection(engine)
                }
                .padding(.horizontal, Self.pageMargin)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Tap anywhere that isn't a word or a control → chip away.
                .contentShape(Rectangle())
                .onTapGesture { activeGloss = nil }
                // The chip floats in the content's coordinate space: it
                // travels with the text and never reflows the page.
                .overlayPreferenceValue(GlossAnchorKey.self) { anchors in
                    GeometryReader { proxy in
                        if let active = activeGloss, !anchors.isEmpty {
                            let rect = anchors
                                .map { proxy[$0] }
                                .reduce(proxy[anchors[0]]) { $0.union($1) }
                            GlossChipOverlay(
                                gloss: active.match.gloss,
                                phraseRect: rect,
                                containerSize: proxy.size,
                                margin: DSSpacing.md,
                                onDismiss: { activeGloss = nil }
                            )
                        }
                    }
                    .allowsHitTesting(activeGloss != nil)
                    .animation(DSMotion.spring, value: activeGloss)
                }
            }
            .pullDismissBounce()
        }
    }

    /// Minimal chrome — a way out. The page carries its own identity; no
    /// hairline: a page isn't a run.
    private var chrome: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("read-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.sm)
    }

    // Style and tier worn lightly: one tracked caption over the headline.
    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Eyebrow("\(styleLabel) · Tier \(passage.tier) · \(passage.wordCount) words")
            Text(passage.title)
                .font(DSType.readerTitle)
                .tracking(-0.4)
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    private var styleLabel: String {
        passage.style.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Body

    @ViewBuilder
    private var passageBody: some View {
        if passage.style == "texto" {
            textoBody
        } else {
            proseBody
        }
    }

    /// Blank lines are paragraph breaks (a full beat of air); single
    /// newlines are listing lines (times, addresses) and stay close-set.
    private var proseBody: some View {
        var lines: [(id: Int, text: String, topPadding: CGFloat)] = []
        for (p, paragraph) in passage.body.components(separatedBy: "\n\n").enumerated() {
            let paragraphLines = paragraph
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for (l, line) in paragraphLines.enumerated() {
                lines.append((
                    id: lines.count,
                    text: line,
                    topPadding: lines.isEmpty ? 0
                        : (l == 0 && p > 0 ? DSSpacing.lg + DSSpacing.xs : DSSpacing.xs + 2)
                ))
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.id) { line in
                GlossTextView(
                    paragraphId: line.id,
                    text: line.text,
                    gloss: gloss,
                    active: $activeGloss
                )
                .padding(.top, line.topPadding)
            }
        }
    }

    /// The texto treatment: the exchange rhythm made visible — sender as a
    /// micro-label, the second voice inset a step — while the text stays
    /// text. No balloons.
    private var textoBody: some View {
        let messages = textoMessages
        let firstSender = messages.first?.sender
        return VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if let sender = message.sender {
                        Eyebrow(sender, color: DSColor.textTertiary, micro: true)
                    }
                    GlossTextView(
                        paragraphId: index,
                        text: message.text,
                        gloss: gloss,
                        active: $activeGloss
                    )
                }
                .padding(.leading,
                         message.sender != nil && message.sender != firstSender
                            ? DSSpacing.xxl : 0)
            }
        }
    }

    private var textoMessages: [(sender: String?, text: String)] {
        passage.body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                guard let separator = line.range(of: " : ") else {
                    return (nil, line)
                }
                return (String(line[..<separator.lowerBound]),
                        String(line[separator.upperBound...]))
            }
    }

    // MARK: Questions (end-of-chapter style)

    private func questionSection(_ engine: ReadEngine) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            Hairline()
                .padding(.top, DSSpacing.xxl)
                .padding(.bottom, DSSpacing.sm)

            Eyebrow("Did it land?")

            ForEach(Array(engine.questions.enumerated()), id: \.offset) { index, question in
                questionBlock(engine, question: question, index: index)
            }

            if engine.allAnswered {
                doneBlock(engine)
                    .transition(.opacity.combined(with: .offset(y: 14)))
            }
        }
    }

    private func questionBlock(
        _ engine: ReadEngine, question: ComprehensionQuestion, index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(question.question)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
            VStack(spacing: 0) {
                Hairline()
                ForEach(Array(question.options.enumerated()), id: \.offset) { option, text in
                    optionButton(engine, questionIndex: index, option: option,
                                 text: text, question: question)
                    Hairline()
                }
            }
        }
    }

    /// De-carded answer rows: a mono letter + the option, chosen one tinted by
    /// grade, the correct one revealed green on a miss. Quiet.
    private func optionButton(
        _ engine: ReadEngine, questionIndex: Int, option: Int,
        text: String, question: ComprehensionQuestion
    ) -> some View {
        let selected = engine.answers[questionIndex]
        let answered = selected != nil
        let isChosen = selected == option
        let isCorrect = option == question.answerIndex
        let tint: Color? = if answered && isChosen {
            isCorrect ? DSColor.gradeSuccess : DSColor.gradeFailure
        } else if answered && isCorrect {
            DSColor.gradeSuccess
        } else {
            nil
        }
        let letters = ["a", "b", "c", "d", "e"]
        return Button { engine.answer(question: questionIndex, option: option) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                Text(letters[min(option, letters.count - 1)])
                    .font(DSType.monoMicro).tracking(DSType.microTracking)
                    .foregroundStyle(tint ?? DSColor.textTertiary)
                    .frame(width: 14, alignment: .leading)
                Text(text)
                    .font(DSType.body.weight(answered && isCorrect ? .medium : .regular))
                    .foregroundStyle(tint ?? DSColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(answered)
        .accessibilityIdentifier("question-\(questionIndex)-option-\(option)")
    }

    /// The quiet done state: one line and a way back.
    private func doneBlock(_ engine: ReadEngine) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            MonoData("\(engine.correctCount) of \(engine.questions.count) · marked as read",
                     color: DSColor.textSecondary)
            Button { dismiss() } label: {
                Text("Done")
                    .font(DSType.body.weight(.medium))
                    .foregroundStyle(DSColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DSColor.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, DSSpacing.sm)
    }
}
