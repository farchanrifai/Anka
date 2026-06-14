import Foundation
import SwiftData

/// One day's spend total, used by the weekly bar chart.
struct DailySpend {
    let date: Date
    let total: Double
}

struct WeeklyHighlightData {
    /// 7 entries, oldest → newest.
    let days: [DailySpend]
    let dailyAverage: Double
    let descriptiveText: String
}

struct MonthlyHighlightData {
    let thisMonthAvgPerDay: Double
    let lastMonthAvgPerDay: Double
    let thisMonthLabel: String
    let lastMonthLabel: String
    let descriptiveText: String
}

struct DailyHighlightData {
    let todayTotal: Double
    let averageTotal: Double
    /// Running cumulative spend today, ordered by time.
    let cumulativeToday: [(time: Date, amount: Double)]
    /// Typical cumulative spend by hour-of-day, averaged over the trailing window.
    let cumulativeAverage: [(time: Date, amount: Double)]
    let currentTimeMarker: Date
    let descriptiveText: String
    let hasEnoughDataForChart: Bool
}

/// Rule-based, on-device spending insights for the Highlights page.
/// No AI/network — everything below is plain arithmetic over expense transactions.
@MainActor
final class HighlightInsightEngine {
    private let expenses: [Transaction]
    private let lookbackDays = 30

    init(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.type == TransactionType.expense },
            sortBy: [SortDescriptor(\.date)]
        )
        expenses = (try? modelContext.fetch(descriptor)) ?? []
    }

    func weeklyHighlight() -> WeeklyHighlightData {
        let todayStart = Date().startOfDay
        let days = (0..<7).reversed().map { offset -> DailySpend in
            let day = todayStart.addingDays(-offset)
            let total = sum(from: day, to: day.addingDays(1))
            return DailySpend(date: day, total: total)
        }
        let average = days.reduce(0) { $0 + $1.total } / Double(days.count)
        return WeeklyHighlightData(
            days: days,
            dailyAverage: average,
            descriptiveText: "You averaged \(average.rupiah) a day over the last 7 days."
        )
    }

    func monthlyHighlight() -> MonthlyHighlightData {
        let now = Date()
        let thisMonthStart = now.startOfMonth
        let daysElapsed = max(1, Calendar.current.component(.day, from: now))
        let thisMonthAvg = sum(from: thisMonthStart, to: thisMonthStart.startOfNextMonth) / Double(daysElapsed)

        let lastMonthStart = thisMonthStart.addingMonths(-1)
        let daysInLastMonth = Calendar.current.range(of: .day, in: .month, for: lastMonthStart)?.count ?? 30
        let lastMonthAvg = sum(from: lastMonthStart, to: thisMonthStart) / Double(daysInLastMonth)

        let descriptiveText: String
        if lastMonthAvg == 0 || abs(thisMonthAvg - lastMonthAvg) / max(lastMonthAvg, 1) < 0.02 {
            descriptiveText = "Your daily spending is about the same as last month."
        } else if thisMonthAvg > lastMonthAvg {
            descriptiveText = "This month, you're spending more per day than last month."
        } else {
            descriptiveText = "This month, you're spending less per day than last month."
        }

        return MonthlyHighlightData(
            thisMonthAvgPerDay: thisMonthAvg,
            lastMonthAvgPerDay: lastMonthAvg,
            thisMonthLabel: thisMonthStart.monthName,
            lastMonthLabel: lastMonthStart.monthName,
            descriptiveText: descriptiveText
        )
    }

    func dailyHighlight() -> DailyHighlightData {
        let now = Date()
        let todayStart = now.startOfDay

        let todays = expenses
            .filter { $0.date >= todayStart && $0.date < todayStart.addingDays(1) }
            .sorted { $0.createdAt < $1.createdAt }
        let todayTotal = todays.reduce(0) { $0 + $1.amount }

        var running = 0.0
        let cumulativeToday = todays.map { tx -> (time: Date, amount: Double) in
            running += tx.amount
            return (time: tx.createdAt, amount: running)
        }

        let lookbackStart = todayStart.addingDays(-lookbackDays)
        let lookbackExpenses = expenses.filter { $0.date >= lookbackStart && $0.date < todayStart }
        let averageTotal = lookbackExpenses.reduce(0) { $0 + $1.amount } / Double(lookbackDays)

        let cumulativeAverage: [(time: Date, amount: Double)] = (0...23).map { hour in
            let hourDate = Calendar.current.date(byAdding: .hour, value: hour, to: todayStart) ?? todayStart
            let cumulative = lookbackExpenses
                .filter { Calendar.current.component(.hour, from: $0.date) <= hour }
                .reduce(0) { $0 + $1.amount }
            return (time: hourDate, amount: cumulative / Double(lookbackDays))
        }

        let descriptiveText: String
        if todayTotal < averageTotal * 0.7 {
            descriptiveText = "You're spending less than you usually do by this point."
        } else if todayTotal > averageTotal * 1.3 {
            descriptiveText = "You're spending more than you usually do by this point."
        } else {
            descriptiveText = "Your spending today is on track."
        }

        return DailyHighlightData(
            todayTotal: todayTotal,
            averageTotal: averageTotal,
            cumulativeToday: cumulativeToday,
            cumulativeAverage: cumulativeAverage,
            currentTimeMarker: now,
            descriptiveText: descriptiveText,
            hasEnoughDataForChart: todays.count >= 2 && !lookbackExpenses.isEmpty
        )
    }

    private func sum(from start: Date, to end: Date) -> Double {
        let interval = DateInterval(start: start, end: end)
        return expenses.filter { interval.containsHalfOpen($0.date) }.reduce(0) { $0 + $1.amount }
    }
}
