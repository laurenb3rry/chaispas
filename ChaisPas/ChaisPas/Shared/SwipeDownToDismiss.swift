import SwiftUI
import UIKit

// MARK: - Swipe down to dismiss (non-scrolling players)

/// Interactive swipe-down-to-dismiss for a full-screen player whose main
/// surface does NOT scroll (the drill stage, a scenario, the vocab pager).
/// Uses a normal `.gesture` so child gestures keep priority — the tap-to-reveal
/// and tap-to-advance still fire; this drag only claims a real downward drag.
/// For scrolling players use `PullToDismissDetector`.
struct SwipeDownToDismiss: ViewModifier {
    var enabled: Bool = true
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        // Attach the drag only when enabled — an inert-but-attached gesture
        // still competes for (and blocks) an underlying ScrollView's overscroll.
        if enabled {
            content.offset(y: offset).gesture(gesture)
        } else {
            content
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard enabled, isDownward(value) else { return }
                offset = reduceMotion ? 0 : value.translation.height * 0.85
            }
            .onEnded { value in
                let dismiss = enabled && isDownward(value)
                    && (value.translation.height > 130
                        || value.predictedEndTranslation.height > 340)
                if dismiss {
                    onDismiss()
                } else if offset != 0 {
                    withAnimation(DSMotion.spring) { offset = 0 }
                }
            }
    }

    private func isDownward(_ value: DragGesture.Value) -> Bool {
        value.translation.height > 0
            && value.translation.height > abs(value.translation.width)
    }
}

extension View {
    func swipeDownToDismiss(
        enabled: Bool = true, perform onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(SwipeDownToDismiss(enabled: enabled, onDismiss: onDismiss))
    }
}

// MARK: - Pull down to dismiss (scrolling players)

/// Dismisses a scrolling player when its content is pulled down past the top.
/// Reads the enclosing `UIScrollView.contentOffset` directly — the reliable
/// source of truth for overscroll — rather than inferring it from SwiftUI
/// layout geometry (which doesn't report rubber-band overscroll here). It uses
/// the scroll view's own gesture, so taps and scrolling are untouched, and you
/// only ever pull down when there's nothing above to reveal.
///
/// Place it (zero-size) inside a ScrollView's content, and pair the ScrollView
/// with `.pullDismissBounce()` so even a short page can be pulled.
struct PullToDismissDetector: UIViewRepresentable {
    var threshold: CGFloat = 90
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        context.coordinator.configure(threshold: threshold, onDismiss: onDismiss)
        DispatchQueue.main.async { context.coordinator.attach(from: probe) }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.configure(threshold: threshold, onDismiss: onDismiss)
        if context.coordinator.scrollView == nil {
            DispatchQueue.main.async { context.coordinator.attach(from: uiView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var onDismiss: (() -> Void)?
        private var threshold: CGFloat = 90
        private(set) weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var fired = false

        func configure(threshold: CGFloat, onDismiss: @escaping () -> Void) {
            self.threshold = threshold
            self.onDismiss = onDismiss
        }

        func attach(from view: UIView) {
            var candidate = view.superview
            while let current = candidate, !(current is UIScrollView) {
                candidate = current.superview
            }
            guard let scroll = candidate as? UIScrollView else { return }
            scrollView = scroll
            observation = scroll.observe(\.contentOffset, options: [.new]) {
                [weak self] scroll, _ in
                guard let self else { return }
                let overscroll = -(scroll.contentOffset.y + scroll.adjustedContentInset.top)
                if overscroll <= 2 { self.fired = false }
                if overscroll > self.threshold, !self.fired,
                   scroll.isDragging || scroll.isDecelerating {
                    self.fired = true
                    self.onDismiss?()
                }
            }
        }
    }
}

extension View {
    /// Pair with a `PullToDismissDetector` inside the content — forces the
    /// scroll to always bounce so even a short page can be pulled down.
    func pullDismissBounce() -> some View {
        scrollBounceBehavior(.always, axes: .vertical)
    }
}
