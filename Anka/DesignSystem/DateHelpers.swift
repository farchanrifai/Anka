import Foundation

// MARK: - Shared formatters (DateFormatter is expensive to allocate — never create inline)
private enum SharedDateFormatter {
    static let relative:       DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d";        return f }()
    static let section:        DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d";       return f }()
    static let fullDate:       DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d, yyyy"; return f }()
    static let monthName:      DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM";               return f }()
    static let shortMonthName: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM";                return f }()
    static let monthYear:      DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy";          return f }()
    static let weekLabel:      DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d";              return f }()
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

    var monthInterval: DateInterval {
        DateInterval(start: startOfMonth, end: endOfMonth)
    }

    nonisolated var startOfWeek: Date {
        let comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return Calendar.current.date(from: comps) ?? self
    }

    var weekInterval: DateInterval {
        let start = startOfWeek
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// "Jun 4" — shared formatter, used for weekly trend chart axis labels.
    var weekLabel: String { SharedDateFormatter.weekLabel.string(from: self) }

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

/// "Jun 4–10" — used by `WeeklySpendData` to label weekly trend chart bars.
func formatWeekRange(start: Date, end: Date) -> String {
    "\(start.weekLabel)–\(end.weekLabel)"
}
