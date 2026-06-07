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
    var isLoading: Bool = false

    /// Encodes every dependency of the cached vars so `.task(id:)` reruns
    /// whenever the data or selected month changes.
    var refreshKey: String {
        "\(dataVersion)-\(currentMonth.timeIntervalSince1970)"
    }

    var monthLabel: String { currentMonth.monthYearLabel }
    var shortMonthLabel: String { currentMonth.monthName }

    // MARK: - Navigation

    func navigateMonth(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentMonth = next.startOfMonth
        }
    }

    func resetToCurrentMonth() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentMonth = Date().startOfMonth
        }
    }

    var isOnCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Async refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Snapshot value types on the main actor.
        let txSnaps  = transactions.map(StatsTxSnap.init)
        let interval = currentMonth.monthInterval
        let catMeta: [UUID: (name: String, colorHex: String)] = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, ($0.name, $0.colorHex)) }
        )

        // 2. Heavy aggregation off-main.
        let result = await Task.detached(priority: .userInitiated) {
            // Expense only — the donut shows where the user's money goes.
            let monthExpenses = txSnaps.filter {
                $0.type == .expense && interval.contains($0.date)
            }

            var totals: [UUID: Double] = [:]
            var total: Double = 0
            for snap in monthExpenses {
                guard let cid = snap.categoryID else { continue }
                totals[cid, default: 0] += snap.amount
                total += snap.amount
            }
            let sorted = totals.sorted { $0.value > $1.value }
            return (sorted, total)
        }.value

        guard !Task.isCancelled else { return }

        monthTotal = result.1
        categorySpend = result.0.compactMap { catID, amount in
            guard let meta = catMeta[catID] else { return nil }
            return CategorySpendData(
                id: catID.uuidString,
                name: meta.name,
                color: Color(hex: meta.colorHex),
                amount: amount
            )
        }
    }
}
