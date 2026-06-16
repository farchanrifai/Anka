import Observation
import SwiftData
import SwiftUI
import Foundation

// MARK: - StatsViewModel

@MainActor
@Observable
final class StatsViewModel {

    // MARK: - Stored data (fed from view's @Query)

    private(set) var transactions: [Transaction] = []
    private(set) var categories: [Category] = []

    private var dataVersion: Int = 0

    func update(transactions: [Transaction], categories: [Category]) {
        self.transactions = transactions
        self.categories = categories
        dataVersion += 1
    }

    // MARK: - Filter state

    /// First day of the month currently being shown.
    var currentMonth: Date = Date().startOfMonth

    // MARK: - Filter state (mode)

    var balanceMode: BalanceMode = .expense

    // MARK: - Cached output

    private(set) var categorySpend: [CategorySpendData] = []
    /// Sum of category-slice amounts (donut denominator). Expense total for
    /// expense/total modes; income total for income mode.
    private(set) var monthTotal: Double = 0
    private(set) var weeklySpend: [WeeklySpendData] = []
    private(set) var weeklyAverage: Double = 0
    var isLoading: Bool = false

    /// Encodes every dependency of the cached vars so `.task(id:)` reruns
    /// whenever the data, selected month, or mode changes.
    var refreshKey: String {
        "\(dataVersion)-\(currentMonth.timeIntervalSince1970)-\(balanceMode.rawValue)"
    }

    var monthLabel: String { currentMonth.monthYearLabel }
    var shortMonthLabel: String { currentMonth.monthName }

    /// Subtitle under the month label — distinguishes the live month (still
    /// accumulating) from a fully-elapsed past month browsed via swipe.
    var periodType: String {
        isOnCurrentMonth ? "Month to date" : "Monthly summary"
    }

    // MARK: - Navigation

    func navigateMonth(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) else { return }
        withAnimation(.dsSpringSoft) {
            currentMonth = next.startOfMonth
        }
    }

    func resetToCurrentMonth() {
        withAnimation(.dsSpringSoft) {
            currentMonth = Date().startOfMonth
        }
    }

    var isOnCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Async refresh

    func refresh() async {
        guard dataVersion > 0 else { return }

        isLoading = true
        defer { isLoading = false }

        let txSnaps        = transactions.map(TransactionSnapshot.init)
        let interval       = currentMonth.monthInterval
        let catMeta: [UUID: (name: String, colorHex: String, emoji: String)] = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, ($0.name, $0.colorHex, $0.emoji)) }
        )
        let targetCurrency = AppCurrency.code
        let capturedMode   = balanceMode

        let result = await Task.detached(priority: .userInitiated) {
            let allPeriod   = txSnaps.filter { interval.containsHalfOpen($0.date) }
            let expenseSnaps = allPeriod.filter { $0.type == .expense }
            let incomeSnaps  = allPeriod.filter { $0.type == .income }

            // Donut slices: expense categories for expense/total, income for income.
            let donutSnaps: [TransactionSnapshot]
            switch capturedMode {
            case .expense, .total: donutSnaps = expenseSnaps
            case .income:          donutSnaps = incomeSnaps
            }

            var totals: [UUID: Double] = [:]
            var donutTotal: Double = 0
            for snap in donutSnaps {
                guard let cid = snap.categoryID else { continue }
                let converted = snap.convertedAmount(to: targetCurrency)
                totals[cid, default: 0] += converted
                donutTotal += converted
            }
            let sorted = totals.sorted { $0.value > $1.value }

            // Weekly: expense or income amounts; total mode nets income − expense.
            var weeklyAgg: [Date: Double] = [:]
            switch capturedMode {
            case .expense:
                for snap in expenseSnaps {
                    weeklyAgg[snap.date.startOfWeek, default: 0] += snap.convertedAmount(to: targetCurrency)
                }
            case .income:
                for snap in incomeSnaps {
                    weeklyAgg[snap.date.startOfWeek, default: 0] += snap.convertedAmount(to: targetCurrency)
                }
            case .total:
                for snap in allPeriod {
                    let amt = snap.type == .income
                        ? snap.convertedAmount(to: targetCurrency)
                        : -snap.convertedAmount(to: targetCurrency)
                    weeklyAgg[snap.date.startOfWeek, default: 0] += amt
                }
            }

            var weeklyRaw: [(weekStart: Date, weekEnd: Date, total: Double, weekNumber: Int)] = []
            var weekStart = interval.start.startOfWeek
            var weekNumber = 1
            while weekStart < interval.end {
                let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                weeklyRaw.append((weekStart, weekEnd, weeklyAgg[weekStart] ?? 0, weekNumber))
                weekStart = weekEnd
                weekNumber += 1
            }

            let activeWeeks = weeklyRaw.filter { abs($0.total) > 0 }
            let weeklyAvg = activeWeeks.isEmpty ? 0 : activeWeeks.reduce(0) { $0 + $1.total } / Double(activeWeeks.count)

            return (sorted, donutTotal, weeklyRaw, weeklyAvg)
        }.value

        guard !Task.isCancelled else { return }

        let newSpend: [CategorySpendData] = result.0.compactMap { catID, amount in
            guard let meta = catMeta[catID] else { return nil }
            return CategorySpendData(
                id: catID.uuidString,
                name: meta.name,
                emoji: meta.emoji,
                color: Color(hex: meta.colorHex),
                amount: amount
            )
        }

        let newWeekly: [WeeklySpendData] = result.2.map {
            WeeklySpendData(weekStart: $0.weekStart, weekEnd: $0.weekEnd, total: $0.total, weekNumber: $0.weekNumber)
        }

        withAnimation(.dsSnappy) {
            monthTotal    = result.1
            categorySpend = newSpend
            weeklySpend   = newWeekly
            weeklyAverage = result.3
        }
    }
}
