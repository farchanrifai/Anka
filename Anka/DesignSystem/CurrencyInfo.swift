import Foundation

/// Curated currency list for the Settings picker and amount formatting.
/// Compiled into both the main app target and the widget extension, like
/// `AppCurrency` (NumberFormatter+Amount.swift).
public struct CurrencyInfo: Identifiable, Equatable {
    public let code: String
    public let symbol: String
    public let name: String
    public let decimalDigits: Int
    /// True when the symbol goes before the amount ("$10"), false when after ("10 zł").
    public let symbolLeading: Bool

    public var id: String { code }

    public static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "IDR", symbol: "Rp",  name: "Indonesian Rupiah", decimalDigits: 0, symbolLeading: true),
        CurrencyInfo(code: "USD", symbol: "$",   name: "US Dollar",        decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "EUR", symbol: "€",   name: "Euro",             decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "GBP", symbol: "£",   name: "British Pound",    decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "JPY", symbol: "¥",   name: "Japanese Yen",     decimalDigits: 0, symbolLeading: true),
        CurrencyInfo(code: "SGD", symbol: "S$",  name: "Singapore Dollar", decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "AUD", symbol: "A$",  name: "Australian Dollar",decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "CAD", symbol: "C$",  name: "Canadian Dollar",  decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "MYR", symbol: "RM",  name: "Malaysian Ringgit",decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "THB", symbol: "฿",   name: "Thai Baht",        decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "PHP", symbol: "₱",   name: "Philippine Peso",  decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "VND", symbol: "₫",   name: "Vietnamese Dong",  decimalDigits: 0, symbolLeading: false),
        CurrencyInfo(code: "INR", symbol: "₹",   name: "Indian Rupee",     decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "CNY", symbol: "¥",   name: "Chinese Yuan",     decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "KRW", symbol: "₩",   name: "South Korean Won", decimalDigits: 0, symbolLeading: true),
        CurrencyInfo(code: "CHF", symbol: "CHF", name: "Swiss Franc",      decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "NZD", symbol: "NZ$", name: "New Zealand Dollar",decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "AED", symbol: "AED", name: "UAE Dirham",       decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "SAR", symbol: "SAR", name: "Saudi Riyal",      decimalDigits: 2, symbolLeading: true),
        CurrencyInfo(code: "MXN", symbol: "MX$", name: "Mexican Peso",     decimalDigits: 2, symbolLeading: true),
    ]

    /// Looks up a currency by ISO code, falling back to a generic 2-decimal,
    /// code-as-symbol entry for codes outside the curated list.
    public static func info(for code: String) -> CurrencyInfo {
        all.first { $0.code == code }
            ?? CurrencyInfo(code: code, symbol: code, name: code, decimalDigits: 2, symbolLeading: true)
    }
}

/// Converts amounts between currencies. Currently a 1:1 no-op — the seam is
/// in place so totals/averages already convert-before-summing, and a live
/// FX-rate provider can be dropped in later without touching call sites.
public enum CurrencyConverter {
    /// ponytail: 1:1 stub rate for every pair. Swap in a live FX provider
    /// (cached daily rates) when available — call sites already convert
    /// before summing, so this is the only place that needs to change.
    public nonisolated static func convert(_ amount: Double, from: String, to: String) -> Double {
        amount
    }
}
