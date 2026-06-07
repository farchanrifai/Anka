import Foundation
import WidgetKit

/// Pushes today's spending snapshot into the App Group `UserDefaults` so the
/// widget extension can render without touching the SwiftData store directly.
///
/// Called from TodayView whenever the transaction set changes. Harmless if
/// no widget is installed — `WidgetCenter.reloadAllTimelines()` just no-ops.
@MainActor
final class WidgetDataWriter {
    static let shared = WidgetDataWriter()
    private init() {}

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

        if let encoded = try? JSONEncoder().encode(Array(recent)) {
            defaults.set(encoded, forKey: WidgetKeys.recentTxs)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
