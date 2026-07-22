import SwiftUI
import UIKit

/// Conjugation-table test (companion to `ConjugationPlayerView`): a random verb
/// and tense, laid out as the same two-column table — pronoun on the left, your
/// answer on the right. The whole table is on screen at once; type a form, hit
/// Return, drop to the next pronoun. Check grades every row at once: green for a
/// right answer, a red strikethrough with the correct form in white beside a
/// wrong one. Runs until every verb × every tense has been drilled.
///
/// Presented like a verb: an ✕ in the chrome and swipe-down to leave.
struct ConjugationTestTablesView: View {
    @Environment(\.dismiss) private var dismiss

    /// One thing to be tested: a verb in a tense, with its expected bare forms.
    struct Prompt: Identifiable {
        let id = UUID()
        let verb: String            // infinitive
        let english: String?
        let tenseLabel: String
        let persons: [String]       // e.g. je/tu/il/on/vous/ils
        let expected: [String]      // bare forms (pronoun stripped), aligned

        /// Stable identity across launches, for the mastered set.
        var key: String { "\(verb)|\(tenseLabel)" }
    }

    /// Every verb × tense that exists; `queue` is this minus the mastered set.
    @State private var allPrompts: [Prompt] = []
    @State private var queue: [Prompt] = []
    @State private var index = 0
    @State private var answers: [String] = []
    @State private var focusedRow: Int?
    @State private var graded = false
    @State private var justMastered = false // the graded verb was all-correct
    @State private var finished = false
    @State private var correctCount = 0     // forms right, whole session
    @State private var gradedCount = 0      // forms graded, whole session
    @State private var masteredKeys: Set<String> = []
    @State private var showingMastered = false

    /// The answer face — kept small so all six rows sit above the keyboard.
    static let answerFont = Font.system(size: 17, weight: .medium)
    /// Height of the soft base the pinned action rides on, above the keyboard.
    static let bottomZoneHeight: CGFloat = 88

    private var prompt: Prompt? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()

            if finished {
                finishView
            } else if let prompt {
                testView(prompt)
            } else {
                ProgressView().tint(DSColor.textSecondary)
            }
        }
        .preferredColorScheme(.dark)
        .swipeDownToDismiss { dismiss() }
        .task { if allPrompts.isEmpty { load() } }
        .fullScreenCover(isPresented: $showingMastered) {
            ConjugationMasteredView(
                entries: masteredEntries,
                onReset: resetMastered
            )
        }
    }

    // MARK: The test

    private func testView(_ prompt: Prompt) -> some View {
        VStack(spacing: 0) {
            chrome("Conjugation · \(index + 1)/\(queue.count)")
            header(prompt)
                .padding(.horizontal, DSSpacing.margin)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
            table(prompt)
                .padding(.horizontal, DSSpacing.margin)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { bottomZone }
    }

    /// Top chrome with the mastered tally: a plain count until you've mastered
    /// something, then a tappable link into the mastered list.
    private func chrome(_ leading: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Eyebrow(leading, micro: true)
                .lineLimit(1)
            if masteredKeys.isEmpty {
                Eyebrow("· 0 mastered", micro: true)
            } else {
                Button { showingMastered = true } label: {
                    Eyebrow("· \(masteredKeys.count) mastered",
                            color: DSColor.accent, micro: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("conjugation-mastered-link")
            }
            Spacer(minLength: DSSpacing.sm)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("player-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.sm)
    }

    /// Mastered prompts, in a stable reading order, for the mastered list.
    private var masteredEntries: [Prompt] {
        allPrompts
            .filter { masteredKeys.contains($0.key) }
            .sorted { ($0.verb, $0.tenseLabel) < ($1.verb, $1.tenseLabel) }
    }

    /// Fixed at the top: the verb, its gloss, the tense.
    private func header(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(prompt.verb)
                .font(DSType.largeTitle)
                .tracking(DSType.largeTitleTracking)
                .foregroundStyle(DSColor.textPrimary)
            if let english = prompt.english {
                Text(english)
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Eyebrow(prompt.tenseLabel, color: DSColor.accent)
                .padding(.top, DSSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The table (pronoun | your answer)

    private func table(_ prompt: Prompt) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(prompt.persons.enumerated()), id: \.offset) { row, person in
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.lg) {
                    Text(person)
                        .font(DSType.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 52, alignment: .leading)
                    answerCell(row, prompt)
                }
                .padding(.vertical, DSSpacing.sm + 2)
            }
        }
    }

    @ViewBuilder
    private func answerCell(_ row: Int, _ prompt: Prompt) -> some View {
        if graded {
            if isCorrect(row) {
                Text(answers[row])
                    .font(Self.answerFont)
                    .foregroundStyle(DSColor.gradeSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: DSSpacing.md) {
                    Text(answers.indices.contains(row) && !answers[row].isEmpty
                         ? answers[row] : "—")
                        .font(Self.answerFont)
                        .foregroundStyle(DSColor.gradeFailure)
                        .strikethrough(color: DSColor.gradeFailure)
                    Text(prompt.expected[row])
                        .font(Self.answerFont)
                        .foregroundStyle(DSColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ConjugationField(
                text: binding(row),
                isLast: row == prompt.persons.count - 1,
                isFocused: focusedRow == row,
                onReturn: { advance(from: row) },
                onBeginEditing: { focusedRow = row }
            )
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Bottom action (pinned above the keyboard)

    private var bottomZone: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: DSColor.background.opacity(0), location: 0),
                    .init(color: DSColor.background, location: 0.6),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.bottomZoneHeight)
            .allowsHitTesting(false)

            primaryButton
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.md)
        }
    }

    private var primaryButton: some View {
        PrimaryButton(graded ? "Next verb" : "Check") { primaryAction() }
            .accessibilityIdentifier("conjugation-test-primary")
    }

    private func primaryAction() {
        if graded { nextVerb() } else if let prompt { grade(prompt) }
    }

    // MARK: Completion

    private var finishView: some View {
        VStack(spacing: 0) {
            chrome("Conjugation · complete")
            Spacer()
            VStack(spacing: DSSpacing.lg) {
                Text("Tables complete")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                MonoData("\(correctCount)/\(gradedCount) forms correct", color: DSColor.accent)
            }
            Spacer()
            PrimaryButton("Done") { dismiss() }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
        }
    }

    // MARK: Row flow + grading

    /// Return steps to the next row; the last row grades the table.
    private func advance(from row: Int) {
        guard let prompt else { return }
        if row >= prompt.persons.count - 1 {
            grade(prompt)
        } else {
            focusedRow = row + 1
        }
    }

    private func grade(_ prompt: Prompt) {
        guard !graded else { return }
        focusedRow = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        let right = prompt.persons.indices.filter { isCorrect($0) }.count
        correctCount += right
        gradedCount += prompt.persons.count
        justMastered = right == prompt.persons.count
        graded = true
        if justMastered {
            DSHaptics.gradeSuccess()
        } else {
            DSHaptics.gradeWarning()
        }
    }

    private func nextVerb() {
        guard graded else { return }
        if justMastered, queue.indices.contains(index) {
            // Graduated: bank it and drop it from the suite; the next prompt
            // slides into this slot, so `index` stays put.
            masteredKeys.insert(queue[index].key)
            Self.persist(masteredKeys)
            queue.remove(at: index)
        } else {
            index += 1
        }
        graded = false
        justMastered = false
        if index >= queue.count {
            finished = true
            return
        }
        answers = Array(repeating: "", count: queue[index].persons.count)
        DispatchQueue.main.async { focusedRow = 0 }
    }

    // MARK: Answer binding + grading

    private func binding(_ row: Int) -> Binding<String> {
        Binding(
            get: { answers.indices.contains(row) ? answers[row] : "" },
            set: { if answers.indices.contains(row) { answers[row] = $0 } }
        )
    }

    private func isCorrect(_ row: Int) -> Bool {
        guard let prompt, answers.indices.contains(row) else { return false }
        return Self.normalize(answers[row]) == Self.normalize(prompt.expected[row])
    }

    // MARK: Building the queue

    private func load() {
        masteredKeys = Self.loadMastered()
        guard let file = try? ContentPackV2.loadLearn(.conjugation) else { return }
        var prompts: [Prompt] = []
        for node in file.nodes {
            guard let table = node.table, let verb = node.infinitive else { continue }
            for tense in ConjugationPlayerView.tenses where table[tense.key] != nil {
                let forms = table[tense.key]!
                let persons = ConjugationPlayerView.persons.filter { forms[$0] != nil }
                guard !persons.isEmpty else { continue }
                let expected = persons.map { Self.strip(person: $0, form: forms[$0]!.formal) }
                prompts.append(Prompt(
                    verb: verb, english: node.english, tenseLabel: tense.label,
                    persons: persons, expected: expected
                ))
            }
        }
        allPrompts = prompts
        rebuildQueue()
    }

    /// (Re)draw the test suite from `allPrompts` minus everything mastered.
    private func rebuildQueue() {
        queue = allPrompts.filter { !masteredKeys.contains($0.key) }.shuffled()
        index = 0
        graded = false
        justMastered = false
        finished = queue.isEmpty
        answers = Array(repeating: "", count: queue.first?.persons.count ?? 6)
        if !finished { DispatchQueue.main.async { focusedRow = 0 } }
    }

    /// Clears every mastered verb and returns them all to the suite.
    private func resetMastered() {
        masteredKeys = []
        Self.persist(masteredKeys)
        rebuildQueue()
    }

    // MARK: Mastered-set persistence

    private static let masteredDefaultsKey = "conjugationTestMasteredForms"

    private static func loadMastered() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: masteredDefaultsKey) ?? [])
    }

    private static func persist(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: masteredDefaultsKey)
    }

    // MARK: Form helpers

    /// The pack's `formal` carries the subject pronoun ("je suis", "j'ai",
    /// "je suis allé"); the test wants only the bare form, so we drop it.
    static func strip(person: String, form: String) -> String {
        if person == "je" {
            if form.hasPrefix("j'") { return String(form.dropFirst(2)) }
            if form.hasPrefix("j’") { return String(form.dropFirst(2)) }
        }
        let prefix = person + " "
        if form.hasPrefix(prefix) { return String(form.dropFirst(prefix.count)) }
        return form
    }

    /// Lenient on case, whitespace and apostrophe style; accents stay
    /// significant (an accent is part of the conjugation).
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Mastered verbs

/// The roll of mastered verbs — each a verb × tense you got fully correct.
/// Presented like a player: an ✕ in the chrome, swipe-down to leave. A
/// "Reset test" at the foot empties the roll and returns every verb to the
/// suite.
private struct ConjugationMasteredView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ConjugationTestTablesView.Prompt]
    let onReset: () -> Void

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                chrome
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        IndexHeader(title: "Mastered", subtitle: "all six pronouns correct")
                            .padding(.horizontal, DSSpacing.margin)
                            .padding(.top, DSSpacing.md)
                            .padding(.bottom, DSSpacing.xl)

                        if entries.isEmpty {
                            Text("Nothing mastered yet.")
                                .font(DSType.body)
                                .foregroundStyle(DSColor.textSecondary)
                                .padding(.horizontal, DSSpacing.margin)
                        } else {
                            Hairline(strong: true)
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                                row(entry)
                                if i < entries.count - 1 { Hairline() }
                            }
                        }

                        resetButton
                            .padding(.top, DSSpacing.xxl)
                    }
                    .padding(.bottom, DSSpacing.xxl)
                }
            }
        }
        .preferredColorScheme(.dark)
        .swipeDownToDismiss { dismiss() }
    }

    private var chrome: some View {
        HStack {
            Eyebrow("Mastered · \(entries.count)", micro: true)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("player-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.sm)
    }

    private func row(_ entry: ConjugationTestTablesView.Prompt) -> some View {
        HStack(spacing: DSSpacing.md) {
            Text(entry.verb)
                .font(DSType.body)
                .foregroundStyle(DSColor.textPrimary)
            if let english = entry.english {
                Text(english)
                    .font(.system(size: 14).italic())
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DSSpacing.md)
            Eyebrow(entry.tenseLabel, color: DSColor.accent)
        }
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.margin)
    }

    private var resetButton: some View {
        Button {
            onReset()
            dismiss()
        } label: {
            Text("Reset test")
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.gradeFailure)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("conjugation-reset-test")
    }
}

// MARK: - The answer field

/// One answer cell. A UIKit text field, both for the French keyboard hint and
/// for precise Return / focus control across the six rows. All white — no
/// accent tint. Only ever *claims* first responder, so the keyboard rides from
/// row to row without a resign dropping it in between.
private struct ConjugationField: UIViewRepresentable {
    @Binding var text: String
    let isLast: Bool
    let isFocused: Bool
    let onReturn: () -> Void
    let onBeginEditing: () -> Void

    func makeUIView(context: Context) -> FrenchTextField {
        let field = FrenchTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.textColor = UIColor(DSColor.textPrimary)
        field.tintColor = UIColor(DSColor.textPrimary)   // white caret
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.accessibilityIdentifier = "conjugation-answer-field"
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: FrenchTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.returnKeyType = isLast ? .done : .next

        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ConjugationField
        init(_ parent: ConjugationField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onBeginEditing()
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

/// Prefers a French keyboard when the user has one installed (falls back to the
/// system default otherwise — a keyboard can't be conjured if it isn't added).
final class FrenchTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first {
            $0.primaryLanguage?.hasPrefix("fr") == true
        } ?? super.textInputMode
    }
}
