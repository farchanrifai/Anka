import Observation
import SwiftData
import Foundation

struct CategoryChartData {
    let category: Category
    let amount: Double
    let percentage: Double
}

struct DailyChartData {
    let date: Date
    let amount: Double
}

@Observable
class ReportsViewModel {
    var transactions: [Transaction] = []
    var selectedMonth: Date = Date()
    var categoryChartData: [CategoryChartData] = []
    var dailyChartData: [DailyChartData] = []
    var totalExpense: Double = 0
    var averagePerDay: Double = 0

    func update(transactions: [Transaction]) {
        self.transactions = transactions
        computeCharts()
    }

    func previousMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        computeCharts()
    }

    func nextMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        computeCharts()
    }

    private func computeCharts() {
        let filtered = transactions.filter { isInSelectedMonth($0.date) && $0.type == .expense }
        let total = filtered.reduce(0) { $0 + $1.amount }
        self.totalExpense = total

        // Category breakdown (donut) — categorized expenses only
        let categorized = filtered.filter { $0.category != nil }
        let grouped = Dictionary(grouping: categorized) { $0.category! }

        self.categoryChartData = grouped
            .map { category, txs -> CategoryChartData in
                let amount = txs.reduce(0) { $0 + $1.amount }
                return CategoryChartData(
                    category: category,
                    amount: amount,
                    percentage: total > 0 ? (amount / total) * 100 : 0
                )
            }
            .sorted { $0.amount > $1.amount }

        // Daily trend (bar chart)
        let dailyGrouped = Dictionary(grouping: filtered) { tx -> Date in
            Calendar.current.startOfDay(for: tx.date)
        }

        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        let monthStart = Calendar.current.startOfDay(for: startOfMonth(selectedMonth))
        var dailyData: [DailyChartData] = []

        for day in 0..<daysInMonth {
            if let date = Calendar.current.date(byAdding: .day, value: day, to: monthStart) {
                let dayStart = Calendar.current.startOfDay(for: date)
                let amount = dailyGrouped[dayStart]?.reduce(0) { $0 + $1.amount } ?? 0
                dailyData.append(DailyChartData(date: date, amount: amount))
            }
        }

        self.dailyChartData = dailyData
        self.averagePerDay = daysInMonth > 0 ? total / Double(daysInMonth) : 0
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func isInSelectedMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.month, .year], from: date)
        let selectedComponents = calendar.dateComponents([.month, .year], from: selectedMonth)
        return dateComponents.month == selectedComponents.month && dateComponents.year == selectedComponents.year
    }

    func monthYearLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }
}
