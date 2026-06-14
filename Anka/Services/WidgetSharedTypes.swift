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
    /// Calendar-day string (yyyy-MM-dd) of the snapshot. Widgets compare this
    /// against the current day and zero the totals when stale (W1).
    public static let snapshotDate     = "widget_snapshot_date"
}

/// URL scheme constants for widget deep links (W3).
public enum AnkaDeepLink {
    /// Base URL scheme registered in the main app target's Info.plist.
    public static let scheme = "anka"
    /// Opens the app to the Today screen (default).
    public static let openApp  = URL(string: "anka://open")!
    /// Opens the Add Transaction sheet.
    public static let addTransaction = URL(string: "anka://add")!
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
