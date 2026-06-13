import Observation
import SwiftData
import SwiftUI
import Foundation

// MARK: - Sendable snapshot

private struct StatsTxSnap: Sendable {
    let id: UUID
    let date: Date
    let type: TransactionType
    let amount: Double
    let categoryID: UUID?

    init(_ tx: Transaction) {
        self.id         = tx.id
        self.date       = tx.date
        self.type       = tx.type
        self.amount     = tx.amount
        self.categoryID = tx.category?.id
    }
}

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

    // MARK: - Cached output

    private(set) var categorySpend: [CategorySpendData] = []
    private(set) var monthTotal: Double = 0
    private(set) var incomeTotal: Double = 0
    private(set) var previousMonthExpenseTotal: Double = 0
    private(set) var weeklySpend: [WeeklySpendData] = []
    private(set) var weeklyAverage: Double = 0
    var isLoading: Bool = false

    /// Income minus expenses for the selected month (signed).
    var netTotal: Double { incomeTotal - monthTotal }

    /// Expense change vs the previous month, as a percentage. `nil` when the
    /// previous month had no expenses (no meaningful baseline to compare).
    var expenseDeltaPercent: Double? {
        guard previousMonthExpenseTotal > 0 else { return nil }
        return (monthTotal - previousMonthExpenseTotal) / previousMonthExpenseTotal * 100
    }

    /// Average expense per elapsed day. For the live month this divides by the
    /// number of days *so far*; for a past month it divides by the month's full
    /// day count.
    var dailyAverage: Double {
        let days: Int
        if isOnCurrentMonth {
            days = max(Date().dayOfMonth, 1)
        } else {
            days = Calendar.current.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
        }
        return monthTotal / Double(days)
    }

    /// Short month name of the previous month — e.g. "May" — for the delta pill.
    var previousMonthShortLabel: String { currentMonth.addingMonths(-1).shortMonthName }

    /// Encodes every dependency of the cached vars so `.task(id:)` reruns
    /// whenever the data or selected month changes.
    var refreshKey: String {
        "\(dataVersion)-\(currentMonth.timeIntervalSince1970)"
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
        // `.task(id: refreshKey)` fires once with the pre-feed key (dataVersion
        // 0, empty data) before onAppear's update() restarts it — skip that
        // no-op pass instead of spinning up a detached task during the push.
        guard dataVersion > 0 else { return }

        isLoading = true
        defer { isLoading = false }

        // 1. Snapshot value types on the main actor.
        let txSnaps      = transactions.map(StatsTxSnap.init)
        let interval     = currentMonth.monthInterval
        let prevInterval = currentMonth.addingMonths(-1).monthInterval
        let catMeta: [UUID: (name: String, colorHex: String, emoji: String)] = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, ($0.name, $0.colorHex, $0.emoji)) }
        )

        // 2. Heavy aggregation off-main.
        let result = await Task.detached(priority: .userInitiated) {
            // Expense only — the donut shows where the user's money goes.
            // Half-open membership so a boundary transaction isn't counted in
            // both this month and the next (AUDIT.md D8).
            let monthExpenses = txSnaps.filter {
                $0.type == .expense && interval.containsHalfOpen($0.date)
            }

            // Income total for the month's summary line (not charted).
            let income = txSnaps
                .filter { $0.type == .income && interval.containsHalfOpen($0.date) }
                .reduce(0) { $0 + $1.amount }

            // Previous-month expense total, for the change-vs-last-month pill.
            let prevTotal = txSnaps
                .filter { $0.type == .expense && prevInterval.containsHalfOpen($0.date) }
                .reduce(0) { $0 + $1.amount }

            var totals: [UUID: Double] = [:]
            var total: Double = 0
            for snap in monthExpenses {
                guard let cid = snap.categoryID else { continue }
                totals[cid, default: 0] += snap.amount
                total += snap.amount
            }
            let sorted = totals.sorted { $0.value > $1.value }

            // Weekly aggregation, spanning every week that overlaps the
            // selected month — including weeks with zero spend, so the trend
            // chart's x-axis stays consistent across months.
            var weeklyAgg: [Date: Double] = [:]
            for snap in monthExpenses {
                weeklyAgg[snap.date.startOfWeek, default: 0] += snap.amount
            }
            // Plain Sendable tuples — the `WeeklySpendData` value objects are
            // built on the main actor below (its initializer is main-actor
            // isolated under the project's default-actor-isolation setting, so
            // it can't be constructed inside this detached closure).
            var weeklyRaw: [(weekStart: Date, weekEnd: Date, total: Double, weekNumber: Int)] = []
            var weekStart = interval.start.startOfWeek
            var weekNumber = 1
            while weekStart < interval.end {
                let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                weeklyRaw.append((weekStart, weekEnd, weeklyAgg[weekStart] ?? 0, weekNumber))
                weekStart = weekEnd
                weekNumber += 1
            }

            // Mean of weeks that actually had spend — the trend chart's
            // reference line (zero-spend weeks would drag the average down).
            let spentWeeks = weeklyRaw.filter { $0.total > 0 }
            let weeklyAvg = spentWeeks.isEmpty ? 0 : spentWeeks.reduce(0) { $0 + $1.total } / Double(spentWeeks.count)

            return (sorted, total, weeklyRaw, income, prevTotal, weeklyAvg)
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

        // Animate the donut crossfade + top-categories list to the new month's
        // data (the chart's internal transition needs an enclosing animation).
        withAnimation(.dsSnappy) {
            monthTotal = result.1
            categorySpend = newSpend
            weeklySpend = newWeekly
            incomeTotal = result.3
            previousMonthExpenseTotal = result.4
            weeklyAverage = result.5
        }
    }
}
