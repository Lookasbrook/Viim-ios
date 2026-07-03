import SwiftUI

enum ViimColors {
    static let navy = Color(hex: 0x1A3A5C)
    static let blue = Color(hex: 0x2E75B6)
    static let red = Color(hex: 0xC00000)
    static let green = Color(hex: 0x217346)
    static let gold = Color(hex: 0xE8B932)
    static let success = Color(hex: 0x1FA363)
    static let warning = Color(hex: 0xF29B1D)
    static let danger = Color(hex: 0xD93636)
    static let background = Color(hex: 0xF2F5F8)
    static let text = Color(hex: 0x122A42)
    static let muted = Color(hex: 0x6B7B8C)
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
