import SwiftUI

struct DSColor {
    // MARK: — Accent
    static let accent        = Color(hex: "F26666")      // coral — primary brand
    static let accentSoft    = Color(hex: "F26666").opacity(0.15)

    // MARK: — Backgrounds (adaptive light/dark)
    static let bgPrimary     = Color(UIColor.systemBackground)
    static let bgSecondary   = Color(UIColor.secondarySystemBackground)
    static let bgTertiary    = Color(UIColor.tertiarySystemBackground)
    static let bgGrouped     = Color(UIColor.systemGroupedBackground)
    static let bgCard        = Color(UIColor.secondarySystemGroupedBackground)

    // MARK: — Text (adaptive)
    static let textPrimary   = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textMuted     = Color(UIColor.tertiaryLabel)
    static let textOnAccent  = Color.white

    // MARK: — Semantic
    static let positive      = Color(hex: "34C759")      // green — income
    static let negative      = Color(hex: "F26666")      // coral — expense
    static let separator     = Color(UIColor.separator)
}
