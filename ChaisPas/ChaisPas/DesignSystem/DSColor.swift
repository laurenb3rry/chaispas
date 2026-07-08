import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Near-monochrome palette, dark-first. One quiet accent; semantic
/// green/red reserved exclusively for grade feedback, desaturated.
enum DSColor {
    static let background = Color(hex: 0x0E0E10)
    static let surface = Color(hex: 0x1A1A1D)
    static let textPrimary = Color(hex: 0xF4F4F5)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let accent = Color(hex: 0xE8E3D8)
    static let gradeSuccess = Color(hex: 0x6FA07C)
    static let gradeFailure = Color(hex: 0xB06A6A)
}
