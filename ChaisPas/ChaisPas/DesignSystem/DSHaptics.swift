import UIKit

/// Section 8: light impact on reveal, success/warning notification on
/// grade, soft ticks on shadow-score.
enum DSHaptics {
    static func reveal() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func gradeSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func gradeWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func shadowTick() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }
}
