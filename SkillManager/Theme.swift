import SwiftUI

enum Theme {
    // Agent colors — always the same
    static let claude = Color(hex: 0xE8751A)
    static let codex  = Color(hex: 0x0066FF)
    static let hermes = Color(hex: 0xF5C518)

    // Frequency colors
    static let freqHigh   = Color(hex: 0xBF5AF2)
    static let freqMedium = Color(hex: 0x007AFF)
    static let freqLow    = Color(hex: 0x8E8E93)

    // Adaptive text & UI
    static let textPrimary   = Color(0xF5F5F7)
    static let textSecondary = Color(0xA1A1A6)
    static let textTertiary  = Color(0x6E6E73)
    static let border        = Color(0x38383A)
    static let sidebarActive = Color(0x0A5DC2)

    // Accent
    static let accentBlue = Color(hex: 0x007AFF)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(_ hex: UInt) {
        self.init(hex: hex)
    }
}
