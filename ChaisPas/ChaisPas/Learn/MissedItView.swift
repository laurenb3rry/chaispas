import SwiftData
import SwiftUI

/// MissedIt: the recall bank for anything reported "Missed it" in a drill. Runs
/// like a drill, but you *type* the answer (a French keyboard rides up like the
/// test tables) — English prompt, type it, return to check, then self-grade
/// against the shown answer. Items are drilled at random (never hammering one),
/// and each stays in the bank until it's gotten three times in a row.
struct MissedItView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Resolved sentences for every id still in the bank.
    @State private var pool: [String: Sentence] = [:]
    /// Ids still owed reps this run — an item drops out only when it clears.
    @State private var remaining: [String] = []
    @State private var current: Sentence?
    @State private var typed = ""
    @State private var revealed = false
    @State private var focused = false
    @State private var audio = AudioPlayer()
    @State private var startedAt = Date.now
    @State private var reps = 0
    @State private var cleared = 0

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if current == nil {
                emptyState
            } else {
                content
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task { load() }
    }

    // MARK: Stage

    private var content: some View {
        VStack(spacing: 0) {
            chrome
            Spacer()
            stage
            Spacer()
            footer
        }
    }

    private var chrome: some View {
        HStack {
            Eyebrow("Missed it · \(remaining.count) left", micro: true)
                .lineLimit(1)
            Spacer()
            Button {
                audio.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("missedit-close")
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.top, DSSpacing.sm)
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text(current?.english ?? "")
                .font(revealed ? DSType.englishPrompt : DSType.stagePrompt)
                .foregroundStyle(revealed ? DSColor.textSecondary : DSColor.textPrimary)

            if revealed {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    labeled("You typed", typed.isEmpty ? "—" : typed,
                            font: DSType.stageFrenchSecondary, color: DSColor.textSecondary)
                    labeled("Answer", current?.frenchFormal ?? "",
                            font: DSType.stageFrench, color: DSColor.textPrimary)
                    if let s = current, s.frenchStreet != s.frenchFormal {
                        labeled("On the street", s.frenchStreet,
                                font: DSType.stageFrenchSecondary, color: DSColor.accent)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 12)))
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    MissedItField(text: $typed, isFocused: focused, onReturn: submit)
                        .frame(height: 40)
                    Rectangle().fill(DSColor.surface).frame(height: 1)
                }
                .padding(.top, DSSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.margin)
    }

    /// Only shows once the answer is on screen; typing lives above the keyboard.
    @ViewBuilder
    private var footer: some View {
        ZStack {
            if revealed {
                HStack(spacing: DSSpacing.md) {
                    gradeButton("Missed it", correct: false)
                    gradeButton("Got it", correct: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DSSpacing.margin)
        .padding(.bottom, DSSpacing.xxl)
        .frame(height: 110, alignment: .bottom)
    }

    private func gradeButton(_ label: String, correct: Bool) -> some View {
        Button { grade(correct: correct) } label: {
            Text(label)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(correct ? DSColor.background : DSColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(correct ? DSColor.accent : DSColor.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(correct ? "missedit-got-it" : "missedit-missed-it")
    }

    private func labeled(_ label: String, _ value: String, font: Font, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Eyebrow(label, micro: true)
            Text(value)
                .font(font)
                .foregroundStyle(color)
        }
    }

    // MARK: Empty / done

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            chrome
            Spacer()
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(reps > 0 ? "Bank clear." : "Nothing missed yet.")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                Text(reps > 0
                     ? "Everything you owed is put to bed."
                     : "Items you miss in a drill land here to be typed back until they stick.")
                    .font(DSType.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DSSpacing.margin)
            Spacer()
            PrimaryButton("Done") { dismiss() }
                .padding(.horizontal, DSSpacing.margin)
                .padding(.bottom, DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Flow

    private func load() {
        let ids = Set(MissedItStore.ids())
        let all = (try? modelContext.fetch(FetchDescriptor<Sentence>())) ?? []
        pool = Dictionary(all.filter { ids.contains($0.id) }.map { ($0.id, $0) },
                          uniquingKeysWith: { a, _ in a })
        remaining = MissedItStore.ids().filter { pool[$0] != nil }
        startedAt = .now
        audio.configureSession()
        selectNext()
    }

    /// Return pressed: freeze the typed answer, reveal the real one, self-grade.
    private func submit() {
        guard !revealed, current != nil else { return }
        focused = false
        withAnimation(DSMotion.spring) { revealed = true }
        DSHaptics.reveal()
        playAudio()
    }

    private func grade(correct: Bool) {
        guard revealed, let s = current else { return }
        audio.stop()
        reps += 1
        if correct { DSHaptics.gradeSuccess() } else { DSHaptics.gradeWarning() }

        // MissedIt reps feed production mastery through the one spine, like any
        // other drill grade (latency unmeasured here — a typed answer has no
        // speak-onset signal).
        try? MasteryModel.recordDrill(
            sentence: s, axis: .production, correct: correct, latencyMs: 0, context: modelContext
        )

        if correct {
            if MissedItStore.markCorrect(sentenceId: s.id) {
                cleared += 1
                remaining.removeAll { $0 == s.id }
            }
        } else {
            MissedItStore.markMissed(sentenceId: s.id)   // stays in the bank
        }
        selectNext()
    }

    /// Pick the next item at random, avoiding an immediate repeat when more than
    /// one item is still owed.
    private func selectNext() {
        let lastId = current?.id
        let candidates = (remaining.count > 1 && lastId != nil)
            ? remaining.filter { $0 != lastId }
            : remaining
        guard let pickId = candidates.randomElement(), let next = pool[pickId] else {
            withAnimation(DSMotion.spring) { current = nil }
            return
        }
        typed = ""
        revealed = false
        withAnimation(DSMotion.spring) { current = next }
        focused = true
    }

    private func playAudio() {
        guard let s = current else { return }
        Task {
            await audio.play(fileName: s.audioRefs.formal,
                             from: s.packVersion == 2 ? .v2Learn : .v1)
        }
    }
}

// MARK: - Typed answer field

/// The typed-answer line: a French keyboard (dark) when one's installed, no
/// autocorrect, return-to-check. Rides up over the prompt like the test tables.
private struct MissedItField: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onReturn: () -> Void

    func makeUIView(context: Context) -> FrenchTextField {
        let field = FrenchTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.textColor = UIColor(DSColor.textPrimary)
        field.tintColor = UIColor(DSColor.accent)
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.attributedPlaceholder = NSAttributedString(
            string: "type it in French",
            attributes: [.foregroundColor: UIColor(DSColor.textTertiary)]
        )
        field.accessibilityIdentifier = "missedit-answer-field"
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: FrenchTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MissedItField
        init(_ parent: MissedItField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}
