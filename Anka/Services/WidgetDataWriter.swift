import Foundation
import WidgetKit

extension Notification.Name {
    /// Posted after any successful transaction mutation (add/edit/delete via the
    /// sheet, CSV import, backup restore). A central observer in the Today views
    /// re-fetches and rewrites widget data so changes that don't alter the
    /// `@Query` array identity — e.g. editing only a transaction's amount — still
    /// propagate to the dashboard + widgets (AUDIT.md X2).
    static let ankaDataDidChange = Notification.Name("anka.dataDidChange")
}

/// Pushes today's spending snapshot into the App Group `UserDefaults` so the
/// widget extension can render without touching the SwiftData store directly.
///
/// Central data-changed hook (AUDIT.md X2): every mutation site (save, delete,
/// import, restore) should call `updateWidgetData` so the widget always reflects
/// the latest state. The `snapshotDate` (W1) lets the widget zero stale totals
/// after midnight.
@MainActor
final class WidgetDataWriter {
    static let shared = WidgetDataWriter()
    private init() {}

    /// Calendar-day formatter shared across write + read (widgets use the same
    /// file, so format is consistent).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func updateWidgetData(transactions: [Transaction]) {
        let todayTxs = transactions.filter { Calendar.current.isDateInToday($0.date) }

        let expense = todayTxs
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }

        let income = todayTxs
            .filter { $0.type == .income }
            .reduce(0.0) { $0 + $1.amount }

        let recent = todayTxs
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { tx in
                WidgetTransaction(
                    id: tx.id.uuidString,
                    amount: tx.amount,
                    categoryName: tx.category?.name ?? "Uncategorized",
                    categoryEmoji: tx.category?.emoji ?? "💳",
                    note: tx.note,
                    isExpense: tx.type == .expense
                )
            }

        guard let defaults = UserDefaults(suiteName: WidgetKeys.suiteName) else {
            // App Group not registered (entitlement missing or mismatched).
            // Silent — main app continues working; widget just won't update.
            return
        }

        defaults.set(expense, forKey: WidgetKeys.todayExpense)
        defaults.set(income, forKey: WidgetKeys.todayIncome)
        defaults.set(Date(), forKey: WidgetKeys.lastUpdated)
        // Store the calendar day so the widget can detect stale data after
        // midnight without the main app opening (W1).
        defaults.set(Self.dayFormatter.string(from: Date()), forKey: WidgetKeys.snapshotDate)

        if let encoded = try? JSONEncoder().encode(Array(recent)) {
            defaults.set(encoded, forKey: WidgetKeys.recentTxs)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
