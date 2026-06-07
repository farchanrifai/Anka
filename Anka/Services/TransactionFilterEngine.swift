import Foundation

// TODO: Phase 7+ — port TransactionFilter type, Double.idrShort, Date.startOfMonth
// helpers from Spendy. Gated out until callers + supporting types exist.
#if ENABLE_TRANSACTION_FILTER_ENGINE
public struct TransactionFilterEngine {

    public static func apply(_ filter: TransactionFilter, to transactions: [Transaction]) -> [Transaction] {
        guard filter.isActive else { return transactions }
        return transactions.filter {
            matchesSearch(filter, $0) &&
            matchesDate(filter, $0) &&
            matchesCategory(filter, $0) &&
            matchesAmount(filter, $0)
        }
    }

    private static func matchesSearch(_ f: TransactionFilter, _ tx: Transaction) -> Bool {
        guard !f.searchText.isEmpty else { return true }
        let q = f.searchText.lowercased()
        return tx.note?.lowercased().contains(q) == true ||
               tx.category?.name.lowercased().contains(q) == true ||
               tx.amount.idrShort.contains(q)
    }

    private static func matchesDate(_ f: TransactionFilter, _ tx: Transaction) -> Bool {
        let cal = Calendar.current
        let now = Date.now
        switch f.dateRange {
        case .allTime:   return true
        case .today:     return cal.isDateInToday(tx.date)
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return tx.date >= start
        case .thisMonth:
            return tx.date >= now.startOfMonth
        case .last3:
            let start = cal.date(byAdding: .month, value: -3, to: now)!
            return tx.date >= start
        case .custom:
            return tx.date >= f.customStart && tx.date <= f.customEnd
        }
    }

    private static func matchesCategory(_ f: TransactionFilter, _ tx: Transaction) -> Bool {
        guard !f.selectedCategories.isEmpty else { return true }
        return f.selectedCategories.contains(tx.category?.name ?? "")
    }

    private static func matchesAmount(_ f: TransactionFilter, _ tx: Transaction) -> Bool {
        if let min = f.amountMin, tx.amount < min { return false }
        if let max = f.amountMax, tx.amount > max { return false }
        return true
    }
}
#endif

