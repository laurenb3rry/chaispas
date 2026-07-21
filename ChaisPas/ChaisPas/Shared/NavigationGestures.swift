import UIKit

/// Full-width interactive swipe-back. iOS only pops from the very left edge,
/// and Home hiding its navigation bar disables even that for the whole stack.
/// This adds a full-width pan that drives the SAME interactive-pop transition
/// (so the previous screen slides in natively) and only begins on a rightward
/// horizontal pan — vertical scrolling and row taps are left untouched. Applies
/// to every pushed screen (the mode index screens); full-screen-cover players
/// aren't in the stack, so they're unaffected (they use pull/swipe-to-dismiss).
extension UINavigationController: UIGestureRecognizerDelegate {
    private static var fullWidthBackKey: UInt8 = 0

    private var fullWidthBackPan: UIPanGestureRecognizer {
        if let existing = objc_getAssociatedObject(self, &Self.fullWidthBackKey)
            as? UIPanGestureRecognizer {
            return existing
        }
        let pan = UIPanGestureRecognizer()
        objc_setAssociatedObject(self, &Self.fullWidthBackKey, pan,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return pan
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        // Forward a full-width pan to whatever the edge gesture already drives
        // (the private interactive-pop transition). If the internals ever move,
        // the guards bail and the standard edge gesture still works.
        guard let edge = interactivePopGestureRecognizer,
              let view = edge.view,
              let targets = edge.value(forKey: "targets") else { return }
        let pan = fullWidthBackPan
        guard pan.view == nil else { return }   // add once
        pan.setValue(targets, forKey: "targets")
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let canPop = viewControllers.count > 1 && transitionCoordinator == nil
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan == fullWidthBackPan else {
            // The system edge gesture — keep it working too.
            return canPop
        }
        let velocity = pan.velocity(in: pan.view)
        let isRightward = velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        return canPop && isRightward
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
