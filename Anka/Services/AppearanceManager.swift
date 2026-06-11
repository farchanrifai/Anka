import SwiftUI
import UIKit

/// Drives app-wide appearance: light/dark/system mode + a dark sub-variant
/// (#000000 pure black vs #1A1A1A soft dark).
///
/// Owned by `AnkaApp` as `@State` and injected via `.environment`. Views read
/// it through `@Environment(AppearanceManager.self)` and use the `bgX(_:)`
/// helpers — passing in their `@Environment(\.colorScheme)` — to resolve the
/// right background for the current mode + variant.
///
/// **Why helpers instead of static colors?** UIColor dynamic providers only
/// re-evaluate on trait changes, not on UserDefaults writes — so changing
/// the dark variant wouldn't update visible backgrounds without forcing a
/// trait flip (which causes a visible flash). Routing through `@Observable`
/// methods means a variant change naturally publishes and dependent views
/// re-render, no flicker.
@MainActor
@Observable
final class AppearanceManager {
    static let darkVariantKey = "anka.darkVariant"
    static let appearanceModeKey = "anka.appearanceMode"
    static let todayViewVersionKey = "anka.todayViewVersion"

    enum Mode: String, CaseIterable, Codable {
        case system, light, dark

        var displayName: String {
            switch self {
            case .system: "System"
            case .light:  "Light"
            case .dark:   "Dark"
            }
        }

        var preferredColorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light:  .light
            case .dark:   .dark
            }
        }

        var symbolName: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light:  "sun.max.fill"
            case .dark:   "moon.fill"
            }
        }
    }

    enum TodayViewVersion: String, CaseIterable, Codable {
        case v1, v2

        var displayName: String {
            switch self {
            case .v1: "Original"
            case .v2: "Mail-style header"
            }
        }
    }

    enum DarkVariant: String, CaseIterable, Codable {
        case black, gray

        var displayName: String {
            switch self {
            case .black: "Pure Black"
            case .gray:  "Soft Dark"
            }
        }

        var hexDescription: String {
            switch self {
            case .black: "#000000"
            case .gray:  "#1A1A1A"
            }
        }
    }

    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceModeKey) }
    }

    var darkVariant: DarkVariant {
        didSet { UserDefaults.standard.set(darkVariant.rawValue, forKey: Self.darkVariantKey) }
    }

    var todayViewVersion: TodayViewVersion {
        didSet { UserDefaults.standard.set(todayViewVersion.rawValue, forKey: Self.todayViewVersionKey) }
    }

    /// Current OS color scheme. Written by `AppRouter` on every
    /// `@Environment(\.colorScheme)` change. Used by `effectiveScheme` to
    /// resolve `.system` mode to a *concrete* value, so sheet roots can
    /// always apply a non-nil `.preferredColorScheme(...)`.
    ///
    /// Why concrete-only on sheets:
    /// 1. Passing `nil` to `.preferredColorScheme` on a sheet does not
    ///    release a previously-applied explicit override (the sheet stays
    ///    stuck on the last concrete value — required closing and reopening
    ///    the sheet to fix).
    /// 2. Conditionally omitting the modifier via `@ViewBuilder` instead
    ///    changes the view's structural type, which causes SwiftUI to tear
    ///    down the NavigationStack inside — popping the user back to the
    ///    main Settings page on every mode toggle.
    ///
    /// Always-applied + always-concrete avoids both.
    ///
    /// **Why this is safe**: AppRouter sits inside the WindowGroup's
    /// `.preferredColorScheme(mode.preferredColorScheme)`, so its env
    /// scheme equals the window's effective scheme. For `.system` mode,
    /// `mode.preferredColorScheme == nil` → window follows OS → AppRouter's
    /// env scheme IS the OS scheme. For `.light`/`.dark`, AppRouter's env
    /// scheme reflects our override (but we don't use `osScheme` for those
    /// modes — `effectiveScheme` short-circuits before reading it).
    var osScheme: ColorScheme = .light

    init() {
        let modeRaw = UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? Mode.system.rawValue
        self.mode = Mode(rawValue: modeRaw) ?? .system

        let variantRaw = UserDefaults.standard.string(forKey: Self.darkVariantKey) ?? DarkVariant.black.rawValue
        self.darkVariant = DarkVariant(rawValue: variantRaw) ?? .black

        let todayVersionRaw = UserDefaults.standard.string(forKey: Self.todayViewVersionKey) ?? TodayViewVersion.v1.rawValue
        self.todayViewVersion = TodayViewVersion(rawValue: todayVersionRaw) ?? .v1
    }

    /// True when the dark variant control is meaningful — Light mode disables it.
    var isDarkVariantApplicable: Bool { mode != .light }

    /// The scheme to pass to `.preferredColorScheme(_:)` on sheet roots.
    /// Never nil — for `.system` we substitute the live OS scheme.
    var effectiveScheme: ColorScheme {
        switch mode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return osScheme
        }
    }

    // MARK: - Background resolution
    //
    // Each helper takes the calling view's `@Environment(\.colorScheme)`,
    // which already reflects `.preferredColorScheme(mode.preferredColorScheme)`
    // applied at the app root. So `scheme == .dark` iff the user effectively
    // wants dark (Light: false, Dark: true, System: follows OS).
    //
    // Variant only applies in dark; light always uses system colors.

    func bgPrimary(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color(UIColor.systemBackground) }
        return darkVariant == .gray ? Color(hex: "1A1A1A") : .black
    }

    func bgSecondary(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color(UIColor.secondarySystemBackground) }
        return darkVariant == .gray ? Color(hex: "2C2C2C") : Color(hex: "1C1C1E")
    }

    func bgTertiary(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color(UIColor.tertiarySystemBackground) }
        return darkVariant == .gray ? Color(hex: "3A3A3C") : Color(hex: "2C2C2E")
    }

    func bgGrouped(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color(UIColor.systemGroupedBackground) }
        return darkVariant == .gray ? Color(hex: "1A1A1A") : .black
    }

    func bgCard(_ scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return Color(UIColor.secondarySystemGroupedBackground) }
        return darkVariant == .gray ? Color(hex: "242424") : Color(hex: "1A1A1A")
    }
}
