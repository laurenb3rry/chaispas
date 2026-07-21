import SwiftUI

enum DSMotion {
    /// Baseline spring for all state transitions.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// A slightly softer spring for the player's hero reveal.
    static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.85)
}

/// Physical touch feedback: a spring-weighted press-scale + slight dim.
/// Honours Reduce Motion (falls back to a dim only). Use on tappable rows and
/// the player's tap surfaces where a plain `.plain` style would feel inert.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(DSMotion.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}
