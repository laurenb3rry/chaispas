import SwiftUI

/// The quick-capture input bar, docked directly above the keyboard while the
/// surface behind it shrinks into a card (see `NoteCaptureModifier`). One field
/// that grows from a line to a few and then scrolls, plus a matching send button.
///
/// This view only *gathers* text — persistence, the throw-into-the-screen
/// animation, and teardown are owned by the modifier. Saving is explicit: a tap
/// anywhere outside the bar, a drag down, or dropping the keyboard all cancel
/// without writing. Every dismissal first resigns the keyboard so the bar rides
/// down with it, then hands off — nothing blinks out while the keyboard lingers.
struct NoteComposerView: View {
    /// Raised by the modifier when it wants the bar to bow out — we drop the
    /// keyboard so the bar glides down in step with it.
    var dismissing: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    /// True once we've committed to closing (send or cancel), so the keyboard
    /// resigning as part of that doesn't re-trigger a cancel.
    @State private var handedOff = false
    @FocusState private var focused: Bool

    /// Match the send button, so the bar reads as one clean row.
    private let controlHeight: CGFloat = 36

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // A tap anywhere outside the bar cancels.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { requestCancel() }
            bar
        }
        // A dark keyboard, to sit with the app instead of glaring gray.
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        // The modifier asked us to close — drop the keyboard so the bar rides down.
        .onChange(of: dismissing) { _, now in if now { focused = false } }
        // A hardware/other keyboard dismissal cancels too (but not our own drop).
        .onChange(of: focused) { _, now in
            if !now && !handedOff { requestCancel() }
        }
    }

    private var bar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                field
                sendButton
            }
            .padding(.horizontal, DSSpacing.margin)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(DSColor.background)
        // A downward drag on the bar cancels.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 40,
                       value.translation.height > abs(value.translation.width) {
                        requestCancel()
                    }
                }
        )
    }

    private var field: some View {
        TextField("+note", text: $text, axis: .vertical)
            .lineLimit(1...5)
            .font(.system(size: 17))
            .foregroundStyle(DSColor.textPrimary)
            .tint(DSColor.accent)
            .focused($focused)
            .accessibilityIdentifier("note-composer-field")
            .padding(.horizontal, DSSpacing.md)
            // Sized so a single line matches the send button exactly.
            .frame(minHeight: controlHeight - 2 * 8)
            .padding(.vertical, 8)
            .background(DSColor.surface,
                        in: RoundedRectangle(cornerRadius: controlHeight / 2))
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(canSave ? DSColor.background : DSColor.textTertiary)
                .frame(width: controlHeight, height: controlHeight)
                .background(Circle().fill(canSave ? DSColor.accent : DSColor.surface))
        }
        .disabled(!canSave)
        .accessibilityIdentifier("note-composer-save")
    }

    private func requestCancel() {
        guard !handedOff else { return }
        handedOff = true
        focused = false          // drop the keyboard; the bar rides down with it
        onCancel()
    }

    private func send() {
        guard canSave, !handedOff else { return }
        handedOff = true
        focused = false          // drop the keyboard in step with the throw
        onSubmit(text)
    }
}

#Preview {
    ZStack {
        DSColor.background.ignoresSafeArea()
        NoteComposerView(dismissing: false, onSubmit: { _ in }, onCancel: {})
    }
}
