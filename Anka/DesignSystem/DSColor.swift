import SwiftUI

/// Static palette tokens. **Background tokens default to system colors and do
/// not honor the dark-variant preference.** Views that should follow the
/// user's Pure Black / Soft Dark choice must use the `appearance.bgX(scheme)`
/// helpers on `AppearanceManager` instead — those re-render reliably when
/// the variant changes. DSColor.bg* exists as a fallback for static contexts
/// (widgets, previews, the lock screen overlay) where env isn't readable.
struct DSColor {
    // MARK: — Accent
    static let accent        = Color(hex: "F26666")      // coral — primary brand
    static let accentSoft    = Color(hex: "F26666").opacity(DSOpacity.subtle)

    // MARK: — Backgrounds (system defaults — variant override lives in AppearanceManager)
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
