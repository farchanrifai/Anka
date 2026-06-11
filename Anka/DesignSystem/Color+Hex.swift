import SwiftUI
import UIKit

/// Parses a hex color string — "RGB", "RRGGBB", or "AARRGGBB", with an optional
/// leading '#' — into 0–255 channel values. Shared by the `Color` and `UIColor`
/// initializers below so the parsing logic isn't duplicated.
private func hexChannels(_ hex: String) -> (r: UInt64, g: UInt64, b: UInt64, a: UInt64) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    switch cleaned.count {
    case 3: // RGB (12-bit)
        return ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
    case 6: // RRGGBB (24-bit)
        return (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
    case 8: // AARRGGBB (32-bit)
        return (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
    default:
        return (0, 0, 0, 255)
    }
}

extension Color {
    init(hex: String) {
        let c = hexChannels(hex)
        self.init(
            .sRGB,
            red: Double(c.r) / 255,
            green: Double(c.g) / 255,
            blue: Double(c.b) / 255,
            opacity: Double(c.a) / 255
        )
    }
}

extension UIColor {
    /// Matches `Color(hex:)` — used inside `UIColor(dynamicProvider:)`
    /// closures where SwiftUI's `Color` doesn't work directly.
    convenience init(hex: String) {
        let c = hexChannels(hex)
        self.init(
            red: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: CGFloat(c.a) / 255
        )
    }
}
