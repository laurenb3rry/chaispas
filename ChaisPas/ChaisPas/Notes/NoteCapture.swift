import SwiftUI
import SwiftData

/// Raises the quick-capture composer on a two-finger **pinch** anywhere on this
/// surface, tagging the note with a super-light breadcrumb ("Grammar", "Speak").
///
/// Pinch is deliberate. An earlier version installed a two-finger-tap recognizer
/// on the `UIWindow`; sitting above SwiftUI's gesture system, it arbitrated every
/// touch first and starved single-finger taps across the whole app. A pinch is a
/// native SwiftUI gesture arbitrated inside the view tree, and — needing two
/// fingers moving together — it can never be produced by a tap, scroll, or the
/// app's navigation gestures. So capture never competes with interaction.
///
/// **Capture mode is explicit.** While composing, the surface shrinks into a card
/// pinned to the top with a dim around it, so it's obvious you've stepped out of
/// the app to jot a note. Crucially the surface *ignores the keyboard* — otherwise
/// SwiftUI's keyboard-avoidance would shove the live content up as the composer's
/// keyboard appears (the button/text "jumping" we saw), which reads as broken. We
/// replace that involuntary shove with one deliberate, reversible transform.
///
/// On send the bar throws itself up into the surface and vanishes while the card
/// scales back to fill the page — the note visibly lands in what you were reading.
private struct NoteCaptureModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let context: String

    @State private var composing = false
    /// The brief throw-into-the-screen phase after a save, before teardown.
    @State private var sending = false
    /// The brief bow-out phase after a cancel — keyboard + bar ride down while the
    /// card grows back — before teardown.
    @State private var dismissing = false

    /// How far the surface shrinks in capture mode. Tuned to clear the composer
    /// bar + keyboard on a typical phone; nudge down if the card overlaps the
    /// keyboard on a smaller device, up if there's too much dead space.
    private let cardScale: CGFloat = 0.62
    private let cardCorner: CGFloat = 34
    /// How far the bar flies up as it's "thrown" into the card.
    private let throwRise: CGFloat = 180

    /// True while the surface should be shown as a shrunken card — i.e. actively
    /// composing, not mid throw-out (send) or bow-out (cancel), both of which
    /// grow the card back.
    private var carded: Bool { composing && !sending && !dismissing }

    func body(content: Content) -> some View {
        ZStack {
            // Dim the world around the card. Purely visual — the composer owns the
            // tap-to-cancel so the whole outside area, keyboard included, is one
            // consistent dismissal target.
            Color.black
                .opacity(carded ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            content
                .clipShape(RoundedRectangle(cornerRadius: carded ? cardCorner : 0,
                                            style: .continuous))
                .scaleEffect(carded ? cardScale : 1, anchor: .top)
                .offset(y: carded ? DSSpacing.sm : 0)
                .disabled(composing)
                // Don't let the composer's keyboard reflow the surface — the shove
                // this prevents is the whole reason the redesign exists.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .simultaneousGesture(
                    // minimumScaleDelta keeps a trivial two-finger brush from firing.
                    MagnifyGesture(minimumScaleDelta: 0.1)
                        .onEnded { _ in
                            guard !composing else { return }
                            DSHaptics.reveal()
                            composing = true
                        }
                )

            if composing {
                NoteComposerView(dismissing: dismissing,
                                 onSubmit: submit,
                                 onCancel: beginDismiss)
                    // The throw: bar rises into the re-expanding surface and fades.
                    .offset(y: sending ? -throwRise : 0)
                    .scaleEffect(sending ? 0.4 : 1)
                    .opacity(sending ? 0 : 1)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(DSMotion.spring, value: composing)
        .animation(DSMotion.spring, value: sending)
        .animation(DSMotion.spring, value: dismissing)
    }

    private func submit(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Note(body: trimmed, context: context))
        try? modelContext.save()
        DSHaptics.gradeSuccess()
        // Kick off the throw; tear the overlay down once it lands.
        sending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            composing = false
            sending = false
        }
    }

    /// Cancel: grow the card back and let the composer ride the keyboard down
    /// together, then tear the overlay down once they've settled.
    private func beginDismiss() {
        guard !dismissing, !sending else { return }
        dismissing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            composing = false
            dismissing = false
        }
    }
}

extension View {
    /// Enables two-finger-pinch note capture on this surface. The label is a
    /// super-light breadcrumb recorded on notes taken here ("Grammar", "Speak").
    func noteCapture(_ context: String) -> some View {
        modifier(NoteCaptureModifier(context: context))
    }
}
