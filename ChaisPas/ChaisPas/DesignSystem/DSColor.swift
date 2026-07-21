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

/// Near-monochrome palette, dark-first. Phase 16: structure is carried by
/// hairlines + type + a monospace data layer, not filled cards — so `surface`
/// is now rare (audio buttons, active pills) and two hairline tokens plus a
/// recessive `textTertiary` (the mono data layer) do the structural work.
enum DSColor {
    static let background = Color(hex: 0x0E0E10)
    static let surface = Color(hex: 0x1A1A1D)
    static let textPrimary = Color(hex: 0xF4F4F5)
    static let textSecondary = Color(hex: 0x8E8E93)
    /// The mono data layer — counts, tiers, metadata — recedes to here.
    static let textTertiary = Color(hex: 0x5E5E63)
    static let accent = Color(hex: 0xE8E3D8)
    static let gradeSuccess = Color(hex: 0x6FA07C)
    static let gradeFailure = Color(hex: 0xB06A6A)

    /// Primary structural device — a thin rule between rows.
    static let hairline = Color.white.opacity(0.08)
    /// Slightly stronger rule under a section header.
    static let hairlineStrong = Color.white.opacity(0.14)
}
