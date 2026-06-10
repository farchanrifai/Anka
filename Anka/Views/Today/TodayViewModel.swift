import Observation
import SwiftData
import SwiftUI
import Foundation

// MARK: - Period Filter

enum PeriodFilter: String, CaseIterable, Hashable {
    /// Single navigable month — driven by the dashboard swipe gesture, anchored
    /// to `TodayViewModel.selectedMonth`. Not shown in the filter sheet.
    case month       = "month"
    case last3Months = "3 months"
    case last6Months = "6 months"
    case thisYear    = "this year"
    case custom      = "custom"

    /// Presets offered in the filter sheet (the `.month` case is reached by
    /// swiping the dashboard, not by tapping a pill).
    static let filterOptions: [PeriodFilter] = [.last3Months, .last6Months, .thisYear, .custom]

    var displayString: String {
        switch self {
        case .month:       return "Month"
        case .last3Months: return "3 Months"
        case .last6Months: return "6 Months"
        case .thisYear:    return "This Year"
        case .custom:      return "Custom"
        }
    }

    /// Date interval for the presets that are anchored to "now" (no extra
    /// state). `.month` and `.custom` are resolved on the view model instead,
    /// since they need `selectedMonth` / the custom date bindings.
    var dateInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .last3Months:
            let start = cal.date(byAdding: .month, value: -3, to: now.startOfMonth)!
            return DateInterval(start: start, end: now)
        case .last6Months:
            let start = cal.date(byAdding: .month, value: -6, to: now.startOfMonth)!
            return DateInterval(start: start, end: now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))!
            return DateInterval(start: start, end: now)
        case .month, .custom:
            // Anchored variants — resolved by TodayViewModel.periodInterval.
            return now.monthInterval
        }
    }
}

// MARK: - Balance Mode

enum BalanceMode: String, CaseIterable, Hashable {
    case expense, income, total

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income:  return "Income"
        case .total:   return "Total"
        }
    }
    
    var icon: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income:  return "arrow.down.left"
        case .total:   return "sum"
        }
    }
}

// MARK: - TodayViewModel

@MainActor @Observable final class TodayViewModel {

    // MARK: - Stored data (fed from view's @Query)

    private(set) var transactions: [Transaction] = []
    private(set) var categories: [Category] = []

    /// Incremented each time the view feeds fresh @Query results so dashboardKey
    /// picks up data changes even when the period and filters are unchanged.
    private var dataVersion: Int = 0

    func update(transactions: [Transaction], categories: [Category]) {
        self.transactions = transactions
        self.categories = categories
        dataVersion += 1
    }

    // MARK: - Filter + chart state

    var selectedPeriod: PeriodFilter = .month
    /// Anchor month for `.month` mode — moved by the dashboard swipe gesture.
    var selectedMonth: Date = Date().startOfMonth
    var customStartDate: Date? = nil
    var customEndDate: Date? = nil
    var selectedCategories: [Category] = []
    var balanceMode: BalanceMode = .expense
    var isChartVisible: Bool = true

    /// Default transaction type for the Add sheet — Total falls back to expense.
    var addDefaultType: TransactionType { balanceMode == .income ? .income : .expense }

    // MARK: - Sheet / navigation state

    var showSettings = false
    var showAddTransaction = false
    var showCategoryFilter = false
    var editingTransaction: Transaction? = nil
    var pendingDeleteTransaction: Transaction? = nil

    /// Non-nil when a delete failed to persist — surfaced as an alert in the view.
    var deleteErrorMessage: String? = nil

    // MARK: - Bottom toolbar (search)
    /// Bound to SwiftUI's `.searchable(text:)` — filters the displayed list in
    /// the view layer (no `Task.detached`, no `dashboardKey` invalidation).
    var searchQuery: String = ""

    /// Label shown next to the bottom-bar Filter pill when active.
    /// nil ⇒ no filter → render a plain icon button.
    var filterLabel: String? {
        switch selectedCategories.count {
        case 0:  return nil
        case 1:  return selectedCategories[0].name
        default: return "\(selectedCategories.count) Categories"
        }
    }

    // MARK: - Task gate
    // Encodes every dependency of the cached vars.
    // .task(id: vm.dashboardKey) fires on any filter, mode, or data change.

    var dashboardKey: String {
        let catIDs = selectedCategories.map(\.id.uuidString).sorted().joined(separator: ",")
        let customRange = {
            if let s = customStartDate {
                let e = customEndDate ?? s
                return "\(s.timeIntervalSince1970)-\(e.timeIntervalSince1970)"
            }
            return "none"
        }()
        return "\(dataVersion)-\(selectedPeriod.rawValue)-\(selectedMonth.timeIntervalSince1970)-\(customRange)-\(balanceMode.rawValue)-\(catIDs)"
    }

    // MARK: - Cached output (populated by refreshDashboard)

    /// Period-filtered transactions — avoids re-scanning the full list on every render.
    private(set) var periodTransactions: [Transaction] = []

    /// Filtered, date-sorted, day-grouped transactions for the main list.
    private(set) var groupedByDay: [(date: Date, transactions: [Transaction])] = []

    /// `groupedByDay` further narrowed by `searchQuery` — cheap, view-layer pass
    /// so each keystroke doesn't re-fire the heavy refresh pipeline.
    var displayedGroupedByDay: [(date: Date, transactions: [Transaction])] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groupedByDay }
        return groupedByDay.compactMap { group in
            let matches = group.transactions.filter { tx in
                if let n = tx.note?.lowercased(), n.contains(q) { return true }
                if let cn = tx.category?.name.lowercased(), cn.contains(q) { return true }
                if String(Int(tx.amount)).contains(q) { return true }
                return false
            }
            return matches.isEmpty ? nil : (date: group.date, transactions: matches)
        }
    }

    /// Category totals for the chart bar, sorted descending.
    private(set) var chartData: [(category: Category, total: Double)] = []

    var isLoading: Bool = false

    // MARK: - Derived: Period (cheap — operate on cached periodTransactions)

    var periodInterval: DateInterval {
        switch selectedPeriod {
        case .month:
            return selectedMonth.monthInterval
        case .custom:
            if let start = customStartDate {
                let end = customEndDate ?? start
                // End of day so all transactions on the end date are included.
                let cal = Calendar.current
                let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
                return DateInterval(start: cal.startOfDay(for: start), end: endOfDay)
            }
            return DateInterval(start: Date(), end: Date())
        case .last3Months, .last6Months, .thisYear:
            return selectedPeriod.dateInterval
        }
    }

    /// Label for the period pill shown left of the balance-mode switcher.
    /// In `.month` mode it shows the selected month name (e.g. "May", "June")
    /// driven by the swipe gesture; otherwise it shows the preset's label
    /// ("3 Months", "6 Months", "This Year", "Custom").
    var periodPillLabel: String {
        switch selectedPeriod {
        case .month:
            return selectedMonth.monthName
        case .last3Months, .last6Months, .thisYear, .custom:
            return selectedPeriod.displayString
        }
    }

    /// Swipe-driven month navigation on the dashboard. Moves to the adjacent
    /// month and switches into single-month mode (clearing any custom range).
    /// `delta` is +1 for the next month (swipe left) / -1 for the previous
    /// (swipe right).
    func navigateMonth(by delta: Int) {
        let cal = Calendar.current
        let base = (selectedPeriod == .month) ? selectedMonth : Date().startOfMonth
        guard let next = cal.date(byAdding: .month, value: delta, to: base) else { return }
        selectedPeriod = .month
        customStartDate = nil
        customEndDate = nil
        selectedMonth = next.startOfMonth
    }

    var expenseTotal: Double {
        periodTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var incomeTotal: Double {
        periodTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Derived: Display (cheap — operate on cached periodTransactions)

    var heroAmount: Double {
        if !selectedCategories.isEmpty {
            return filteredTransactions.reduce(0) { $0 + $1.amount }
        }
        switch balanceMode {
        case .expense: return expenseTotal
        case .income:  return incomeTotal
        case .total:   return incomeTotal - expenseTotal
        }
    }

    var filteredTransactions: [Transaction] {
        var txs: [Transaction]
        switch balanceMode {
        case .expense: txs = periodTransactions.filter { $0.type == .expense }
        case .income:  txs = periodTransactions.filter { $0.type == .income }
        case .total:   txs = periodTransactions
        }
        if !selectedCategories.isEmpty {
            let ids = Set(selectedCategories.map { $0.id })
            txs = txs.filter { ids.contains($0.category?.id ?? UUID()) }
        }
        return txs.sorted { $0.date > $1.date }
    }

    var availableCategories: [Category] {
        let ids = Set(selectedCategories.map { $0.id })
        return categories.filter { cat in
            guard !ids.contains(cat.id) else { return false }
            switch balanceMode {
            case .expense: return cat.type == .expense
            case .income:  return cat.type == .income
            case .total:   return true
            }
        }
    }

    // MARK: - Async refresh

    /// Recomputes all cached output vars.
    /// Call via `.task(id: vm.dashboardKey) { await vm.refreshDashboard() }`.
    func refreshDashboard() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Snapshot Sendable value types on the main actor.
        let txSnaps           = transactions.map(TxSnap.init)
        let interval          = periodInterval
        // nil = include both types (Total mode)
        let capturedType: TransactionType? = {
            switch balanceMode {
            case .expense: return .expense
            case .income:  return .income
            case .total:   return nil
            }
        }()
        let capturedCatIDs: Set<UUID>     = Set(selectedCategories.map(\.id))
        let tz                            = TimeZone.current

        // 2. Heavy computation on a background thread.
        let result = await Task.detached(priority: .userInitiated) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz

            // Period filter
            let periodSnaps = txSnaps.filter { interval.contains($0.date) }

            // Filtered + sorted snaps (type + optional category filter)
            var filtered = capturedType == nil ? periodSnaps : periodSnaps.filter { $0.type == capturedType }
            if !capturedCatIDs.isEmpty {
                filtered = filtered.filter { capturedCatIDs.contains($0.categoryID ?? UUID()) }
            }
            filtered.sort { $0.date > $1.date }

            // Group by calendar day → [Date: [UUID]]
            var dayDict: [Date: [UUID]] = [:]
            for snap in filtered {
                let day = cal.startOfDay(for: snap.date)
                dayDict[day, default: []].append(snap.id)
            }
            let sortedDays = dayDict.map { ($0.key, $0.value) }
                                    .sorted { $0.0 > $1.0 }

            // Chart aggregation
            var chartBuckets: [UUID: Double] = [:]
            for snap in periodSnaps where capturedType == nil || snap.type == capturedType {
                if let catID = snap.categoryID {
                    chartBuckets[catID, default: 0] += snap.amount
                }
            }
            let sortedChart = chartBuckets.map { ($0.key, $0.value) }
                                          .sorted { $0.1 > $1.1 }

            return (
                periodIDs:    Set(periodSnaps.map(\.id)),
                dayGroups:    sortedDays,
                chartBuckets: sortedChart
            )
        }.value

        // 3. Back on main: check cancellation, merge IDs with model objects.
        guard !Task.isCancelled else { return }

        let txByID  = Dictionary(transactions.map  { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let catByID = Dictionary(categories.map    { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        periodTransactions = transactions.filter { result.periodIDs.contains($0.id) }

        groupedByDay = result.dayGroups.compactMap { date, ids in
            let txs = ids.compactMap { txByID[$0] }
            return txs.isEmpty ? nil : (date: date, transactions: txs)
        }

        chartData = result.chartBuckets.compactMap { catID, total in
            guard let cat = catByID[catID] else { return nil }
            return (category: cat, total: total)
        }
    }

    // MARK: - Actions

    func handleScrollOffset(_ offset: CGFloat) {
        guard selectedCategories.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isChartVisible = offset <= 180
        }
    }

    func onCategoryFilterChanged(scrollOffset: CGFloat) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChartVisible = selectedCategories.isEmpty && scrollOffset <= 180
        }
    }

    func clearCategoryFilter() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedCategories = []
        }
    }

    func addCategory(_ cat: Category) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !selectedCategories.contains(where: { $0.id == cat.id }) {
                selectedCategories.append(cat)
            }
        }
    }

    func removeCategory(_ cat: Category) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedCategories.removeAll { $0.id == cat.id }
        }
    }

    func requestDelete(_ tx: Transaction) {
        pendingDeleteTransaction = tx
    }

    func confirmDelete(context: ModelContext) {
        guard let tx = pendingDeleteTransaction else { return }
        context.delete(tx)
        do {
            try context.save()
        } catch {
            deleteErrorMessage = "Failed to delete transaction. Please try again."
        }
        pendingDeleteTransaction = nil
    }

    // MARK: - Helpers

    func abbreviatedAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            let m = value / 1_000_000
            return m.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fJt", m)
                : String(format: "%.1fJt", m)
        }
        if value >= 1_000 {
            let k = value / 1_000
            return k.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fK", k)
                : String(format: "%.1fK", k)
        }
        return value.idrShort
    }

    private static let compactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yy"
        return f
    }()

    func shortDateLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return Self.compactDateFormatter.string(from: date)
    }
}

// MARK: - Sendable snapshot

private struct TxSnap: Sendable {
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
