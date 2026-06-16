import Foundation

/// Single source of truth for the app's display currency code.
///
/// Declared here (rather than in a settings file) because this file is
/// compiled into both the main app target AND the widget extension, while
/// settings files may be main-app-only.
enum AppCurrency {
    private static let storageKey   = "anka.defaultCurrency"
    private static let decimalsKey  = "anka.showDecimals"

    /// The user's chosen currency (Settings → Currency). Defaults to "IDR".
    static var code: String {
        get { PlatformPaths.sharedDefaults.string(forKey: storageKey) ?? "IDR" }
        set { PlatformPaths.sharedDefaults.set(newValue, forKey: storageKey) }
    }

    /// When true, forces 2 decimal places on all currency amounts system-wide.
    /// When false (default), uses the currency's natural decimal count (0 for
    /// IDR/JPY, 2 for USD/EUR, etc.).
    static var showDecimals: Bool {
        get { PlatformPaths.sharedDefaults.bool(forKey: decimalsKey) }
        set { PlatformPaths.sharedDefaults.set(newValue, forKey: decimalsKey) }
    }
}

extension NumberFormatter {
    /// Decimal formatter for `digits` fraction digits. Cached per digit count
    /// since `CurrencyInfo` only defines 0 or 2 today.
    static func amount(decimalDigits digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits
        return f
    }

    static let idr = amount(decimalDigits: 0)
}

extension Double {
    /// "IDR 1,234,567" — for labels and rows
    var idrFormatted: String {
        "\(AppCurrency.code) \(idrShort)"
    }
    /// "1,234,567" — the amount only, formatted for the current app currency
    /// (decimal places follow `CurrencyInfo`; "IDR"/"JPY" show 0, "USD"/"EUR" show 2).
    var idrShort: String {
        let info   = CurrencyInfo.info(for: AppCurrency.code)
        let digits = AppCurrency.showDecimals ? 2 : info.decimalDigits
        return NumberFormatter.amount(decimalDigits: digits).string(from: NSNumber(value: self)) ?? "0"
    }
    /// "Rp 1,234,567" / "$1,234.56" — the app's canonical amount rendering,
    /// symbol + amount in the current app currency (AUDIT.md U4).
    var rupiah: String {
        let info = CurrencyInfo.info(for: AppCurrency.code)
        return info.symbolLeading ? "\(info.symbol) \(idrShort)" : "\(idrShort) \(info.symbol)"
    }

    /// "+Rp 1,234,567" / "-$300.00" — signed amount for net/delta values.
    var signedRupiah: String {
        (self < 0 ? "-" : "+") + abs(self).rupiah
    }
}

extension Int {
    var idrFormatted: String { Double(self).idrFormatted }
    var idrShort:     String { Double(self).idrShort }
}
