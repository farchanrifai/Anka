import Observation
import SwiftData
import SwiftUI
import Foundation

// MARK: - Period Filter

enum PeriodFilter: String, CaseIterable, Hashable {
    case thisMonth   = "this month"
    case lastMonth   = "last month"
    case last3Months = "last 3 months"
    case thisYear    = "this year"

    var displayString: String { rawValue }

    var dateInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisMonth:
            return now.monthInterval
        case .lastMonth:
            return cal.date(byAdding: .month, value: -1, to: now)!.monthInterval
        case .last3Months:
            let start = cal.date(byAdding: .month, value: -3, to: now.startOfMonth)!
            return DateInterval(start: start, end: now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))!
            return DateInterval(start: start, end: now)
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

    var selectedPeriod: PeriodFilter = .thisMonth
    var selectedCategories: [Category] = []
    var showingExpense: Bool = true
    var isChartVisible: Bool = true

    // MARK: - Sheet / navigation state

    var showSettings = false
    var showAddTransaction = false
    var editingTransaction: Transaction? = nil
    var pendingDeleteTransaction: Transaction? = nil

    // MARK: - Task gate
    // Encodes every dependency of the cached vars.
    // .task(id: vm.dashboardKey) fires on any filter, mode, or data change.

    var dashboardKey: String {
        let catIDs = selectedCategories.map(\.id.uuidString).sorted().joined(separator: ",")
        return "\(dataVersion)-\(selectedPeriod.rawValue)-\(showingExpense)-\(catIDs)"
    }

    // MARK: - Cached output (populated by refreshDashboard)

    /// Period-filtered transactions — avoids re-scanning the full list on every render.
    private(set) var periodTransactions: [Transaction] = []

    /// Filtered, date-sorted, day-grouped transactions for the main list.
    private(set) var groupedByDay: [(date: Date, transactions: [Transaction])] = []

    /// Category totals for the chart bar, sorted descending.
    private(set) var chartData: [(category: Category, total: Double)] = []

    var isLoading: Bool = false

    // MARK: - Derived: Period (cheap — operate on cached periodTransactions)

    var periodInterval: DateInterval { selectedPeriod.dateInterval }

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
        return showingExpense ? expenseTotal : incomeTotal
    }

    var filteredTransactions: [Transaction] {
        let type: TransactionType = showingExpense ? .expense : .income
        var txs = periodTransactions.filter { $0.type == type }
        if !selectedCategories.isEmpty {
            let ids = Set(selectedCategories.map { $0.id })
            txs = txs.filter { ids.contains($0.category?.id ?? UUID()) }
        }
        return txs.sorted { $0.date > $1.date }
    }

    var availableCategories: [Category] {
        let ids = Set(selectedCategories.map { $0.id })
        let type: TransactionType = showingExpense ? .expense : .income
        return categories.filter { !ids.contains($0.id) && $0.type == type }
    }

    // MARK: - Async refresh

    /// Recomputes all cached output vars.
    /// Call via `.task(id: vm.dashboardKey) { await vm.refreshDashboard() }`.
    func refreshDashboard() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Snapshot Sendable value types on the main actor.
        let txSnaps           = transactions.map(TxSnap.init)
        let interval          = selectedPeriod.dateInterval
        let capturedType: TransactionType = showingExpense ? .expense : .income
        let capturedCatIDs: Set<UUID>     = Set(selectedCategories.map(\.id))
        let tz                            = TimeZone.current

        // 2. Heavy computation on a background thread.
        let result = await Task.detached(priority: .userInitiated) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz

            // Period filter
            let periodSnaps = txSnaps.filter { interval.contains($0.date) }

            // Filtered + sorted snaps (type + optional category filter)
            var filtered = periodSnaps.filter { $0.type == capturedType }
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
            for snap in periodSnaps where snap.type == capturedType {
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
        try? context.save()
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
