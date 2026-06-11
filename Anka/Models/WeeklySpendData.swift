import Foundation

/// One bar in the Stats sheet's weekly trend chart — total expenses for the
/// 7-day window starting at `weekStart` (`weekEnd` is exclusive).
struct WeeklySpendData: Identifiable, Sendable {
    let id: Date              // startOfWeek, for grouping
    let weekStart: Date
    let weekEnd: Date
    let total: Double         // sum of expenses that week

    /// 1-based position of this week within the displayed period (e.g. the
    /// 1st–4th/5th week of the selected month). Relative numbering reads
    /// better here than absolute ISO week numbers, which jump around
    /// year boundaries and don't line up with a month-scoped view.
    let weekNumber: Int

    /// "W1", "W2", … — shown on the chart's x-axis.
    var label: String { "W\(weekNumber)" }

    /// "Jun 4–10" — the underlying date range, for accessibility/detail.
    let dateRangeLabel: String

    init(weekStart: Date, weekEnd: Date, total: Double, weekNumber: Int) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.total = total
        self.weekNumber = weekNumber
        self.id = weekStart

        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
        self.dateRangeLabel = formatWeekRange(start: weekStart, end: lastDay)
    }
}
