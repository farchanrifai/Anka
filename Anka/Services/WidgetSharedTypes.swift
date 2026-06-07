import Foundation

/// Types + keys shared between the main Anka app (writer) and the widget
/// extension (reader). The widget target must include this file in its
/// target membership (Xcode: select file → File Inspector → check AnkaWidgets).
public enum WidgetKeys {
    public static let suiteName        = "group.com.nc.Anka"
    public static let todayExpense     = "widget_today_expense"
    public static let todayIncome      = "widget_today_income"
    public static let recentTxs        = "widget_recent_transactions"
    public static let lastUpdated      = "widget_last_updated"
}

/// Snapshot of a transaction safe to serialise into App Group UserDefaults
/// for the widget. Stays Sendable + Codable so writer and reader stay in sync.
public struct WidgetTransaction: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let amount: Double
    public let categoryName: String
    public let categoryEmoji: String
    public let note: String?
    public let isExpense: Bool

    public init(id: String, amount: Double, categoryName: String, categoryEmoji: String, note: String?, isExpense: Bool) {
        self.id = id
        self.amount = amount
        self.categoryName = categoryName
        self.categoryEmoji = categoryEmoji
        self.note = note
        self.isExpense = isExpense
    }
}

/// Whole-IDR grouped string used by widget glyphs.
/// e.g. 125_000 → "125,000". No "K" suffix (the pasted Phase 7 plan had
/// a "K" suffix without dividing by 1000 — that's a typo).
public extension Double {
    var groupedIDR: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "0"
    }
}
