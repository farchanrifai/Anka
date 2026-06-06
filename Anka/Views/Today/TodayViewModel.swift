import Observation
import SwiftData
import Foundation

struct TransactionGroup {
    let date: Date
    let transactions: [Transaction]
}

@Observable
class TodayViewModel {
    var transactions: [Transaction] = []
    var groupedByDay: [TransactionGroup] = []
    var totalIncome: Double = 0
    var totalExpense: Double = 0
    var heroTotal: Double = 0

    func update(transactions: [Transaction]) {
        self.transactions = transactions
        filterAndGroup()
    }

    private func filterAndGroup() {
        // Filter to this month only
        let filtered = transactions.filter { isThisMonth($0.date) }

        // Calculate totals
        totalIncome = filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        totalExpense = filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        heroTotal = totalIncome - totalExpense

        // Group by day
        let grouped = Dictionary(grouping: filtered) { tx -> Date in
            Calendar.current.startOfDay(for: tx.date)
        }

        self.groupedByDay = grouped
            .sorted { $0.key > $1.key }
            .map { TransactionGroup(date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
    }

    private func isThisMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let dateComponents = calendar.dateComponents([.month, .year], from: date)
        let nowComponents = calendar.dateComponents([.month, .year], from: now)
        return dateComponents.month == nowComponents.month && dateComponents.year == nowComponents.year
    }

    func shortDateLabel(for date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, d MMM"
            return formatter.string(from: date)
        }
    }

    /// Signed daily total: income adds, expense subtracts.
    func dailyTotal(for transactions: [Transaction]) -> Double {
        transactions.reduce(0) { partial, tx in
            partial + (tx.type == .income ? tx.amount : -tx.amount)
        }
    }
}
