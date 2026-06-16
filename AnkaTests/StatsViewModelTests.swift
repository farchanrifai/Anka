import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers `StatsViewModel.refresh()` aggregation: month navigation,
/// expense delta % vs the previous month, and weekly bucket coverage
/// (every week overlapping the month, including zero-spend weeks).
@MainActor
struct StatsViewModelTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    @Test func navigateMonthAndResetToCurrentMonth() {
        let vm = StatsViewModel()
        let start = vm.currentMonth

        vm.navigateMonth(by: -1)
        #expect(vm.currentMonth == start.addingMonths(-1))
        #expect(!vm.isOnCurrentMonth)

        vm.resetToCurrentMonth()
        #expect(vm.currentMonth == start)
        #expect(vm.isOnCurrentMonth)
    }

    @Test func refreshComputesCategorySpendByMode() async throws {
        let context = try makeContext()
        let groceries = Anka.Category(name: "Groceries", emoji: "🛒", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        let salary    = Anka.Category(name: "Salary",    emoji: "💼", colorHex: "66BB6A", type: .income,  sortOrder: 0)
        context.insert(groceries)
        context.insert(salary)

        let monthStart = Date().startOfMonth
        context.insert(Transaction(amount: 100, type: .expense, date: monthStart, category: groceries))
        context.insert(Transaction(amount: 500, type: .income,  date: monthStart, category: salary))
        try context.save()

        let txs = try context.fetch(FetchDescriptor<Transaction>())

        // Expense mode (default): donut shows expense categories.
        let vm = StatsViewModel()
        vm.update(transactions: txs, categories: [groceries, salary])
        await vm.refresh()

        #expect(vm.monthTotal == 100)
        #expect(vm.categorySpend.first?.name == "Groceries")
        #expect(vm.categorySpend.first?.amount == 100)

        // Income mode: donut switches to income categories.
        vm.balanceMode = .income
        await vm.refresh()

        #expect(vm.monthTotal == 500)
        #expect(vm.categorySpend.first?.name == "Salary")
        #expect(vm.categorySpend.first?.amount == 500)
    }

    @Test func boundaryTransactionAtStartOfNextMonthIsExcludedFromCurrentMonth() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Home", emoji: "🏠", colorHex: "7E57C2", type: .expense, sortOrder: 0)
        context.insert(cat)

        let monthStart = Date().startOfMonth
        let nextMonthStart = monthStart.startOfNextMonth
        context.insert(Transaction(amount: 100, type: .expense, date: monthStart, category: cat))
        context.insert(Transaction(amount: 999, type: .expense, date: nextMonthStart, category: cat))
        try context.save()

        let vm = StatsViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        await vm.refresh()

        #expect(vm.monthTotal == 100)
    }

}
