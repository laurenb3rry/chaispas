import SwiftUI

enum DSMotion {
    /// Baseline spring for all state transitions
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}
