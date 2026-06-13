import Foundation

/// Single source of truth for the app's display currency code.
///
/// Declared here (rather than in a settings file) because this file is
/// compiled into both the main app target AND the widget extension, while
/// settings files may be main-app-only.
enum AppCurrency {
    static let code = "IDR"
}

extension NumberFormatter {
    static let idr: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()
}

extension Double {
    /// "IDR 1,234,567" — for labels and rows
    var idrFormatted: String {
        "\(AppCurrency.code) \(NumberFormatter.idr.string(from: NSNumber(value: self)) ?? "0")"
    }
    /// "1,234,567" — for chart center/axis where IDR takes too much space
    var idrShort: String {
        NumberFormatter.idr.string(from: NSNumber(value: self)) ?? "0"
    }
    /// "Rp 1,234,567" — the app's canonical amount rendering. Single source for
    /// the symbol so it isn't re-typed across views (AUDIT.md U4).
    var rupiah: String { "Rp \(idrShort)" }

    /// "+Rp 1,234,567" / "-Rp 300,000" — signed rupiah for net/delta values.
    var signedRupiah: String {
        (self < 0 ? "-" : "+") + abs(self).rupiah
    }
}

extension Int {
    var idrFormatted: String { Double(self).idrFormatted }
    var idrShort:     String { Double(self).idrShort }
}
