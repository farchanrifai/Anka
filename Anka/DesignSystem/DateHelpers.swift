import Foundation

// MARK: - Shared formatters (DateFormatter is expensive to allocate — never create inline)
private enum SharedDateFormatter {
    static let relative:       DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d";        return f }()
    static let section:        DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d";       return f }()
    static let fullDate:       DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d, yyyy"; return f }()
    static let monthName:      DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM";               return f }()
    static let shortMonthName: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM";                return f }()
    static let monthYear:      DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy";          return f }()
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var startOfMonth: Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: comps) ?? self
    }

    var endOfMonth: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth) ?? self
    }

    /// First instant of the *next* month — the exclusive upper bound for a
    /// half-open month range, so a transaction at the month boundary lands in
    /// exactly one month (AUDIT.md D8).
    var startOfNextMonth: Date { startOfMonth.addingMonths(1) }

    /// First instant of the calendar year containing this date. Falls back to
    /// `startOfMonth` if the calendar can't resolve the components (it always
    /// can for the Gregorian calendar, but this avoids a force-unwrap).
    var startOfYear: Date {
        let comps = Calendar.current.dateComponents([.year], from: self)
        return Calendar.current.date(from: comps) ?? startOfMonth
    }

    /// `self` shifted by `months`, falling back to `self` if the shift can't be
    /// computed. Use instead of force-unwrapping `Calendar.date(byAdding:)`.
    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    /// `self` shifted by `days`, with the same safe-fallback contract.
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Half-open month span `[startOfMonth, startOfNextMonth)`. The `end` is the
    /// exclusive boundary; pair it with `DateInterval.containsHalfOpen(_:)` so a
    /// transaction at midnight on the 1st isn't counted in two months (D8).
    var monthInterval: DateInterval {
        DateInterval(start: startOfMonth, end: startOfNextMonth)
    }

    var relativeLabel: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return SharedDateFormatter.relative.string(from: self)
    }

    var sectionLabel: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return SharedDateFormatter.section.string(from: self)
    }

    var fullDateLabel: String    { SharedDateFormatter.fullDate.string(from: self) }
    var monthName: String        { SharedDateFormatter.monthName.string(from: self) }
    var shortMonthName: String   { SharedDateFormatter.shortMonthName.string(from: self) }

    var dayOfMonth: Int { Calendar.current.component(.day, from: self) }
    var month: Int      { Calendar.current.component(.month, from: self) }
    var year: Int       { Calendar.current.component(.year, from: self) }

    /// "May 2026" — shared formatter so the year is never formatted with thousands separator
    var monthYearLabel: String   { SharedDateFormatter.monthYear.string(from: self) }
}

extension DateInterval {
    /// Half-open membership: `start <= date < end`. Unlike `contains(_:)` (which
    /// includes `end`), this counts a transaction at the exclusive upper bound
    /// as belonging to the *next* period — so period filters never double-count
    /// a boundary transaction (AUDIT.md D8).
    nonisolated func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
