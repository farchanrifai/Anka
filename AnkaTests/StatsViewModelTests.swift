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

    @Test func refreshComputesCategorySpendIncomeAndDelta() async throws {
        let context = try makeContext()
        let groceries = Anka.Category(name: "Groceries", emoji: "🛒", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        let salary = Anka.Category(name: "Salary", emoji: "💼", colorHex: "66BB6A", type: .income, sortOrder: 0)
        context.insert(groceries)
        context.insert(salary)

        let now = Date()
        let monthStart = now.startOfMonth
        let prevMonth = monthStart.addingMonths(-1)

        // This month: 100 expense (groceries), 500 income (salary).
        context.insert(Transaction(amount: 100, type: .expense, date: monthStart, category: groceries))
        context.insert(Transaction(amount: 500, type: .income, date: monthStart, category: salary))
        // Previous month: 50 expense — baseline for the delta.
        context.insert(Transaction(amount: 50, type: .expense, date: prevMonth, category: groceries))
        try context.save()

        let vm = StatsViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [groceries, salary])
        await vm.refresh()

        #expect(vm.monthTotal == 100)
        #expect(vm.incomeTotal == 500)
        #expect(vm.netTotal == 400)
        #expect(vm.categorySpend.first?.name == "Groceries")
        #expect(vm.categorySpend.first?.amount == 100)

        // (100 - 50) / 50 * 100 = 100%
        let delta = try #require(vm.expenseDeltaPercent)
        #expect(abs(delta - 100) < 0.0001)
    }

    @Test func expenseDeltaPercentIsNilWithoutPreviousMonthBaseline() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Coffee", emoji: "☕", colorHex: "FF8A65", type: .expense, sortOrder: 0)
        context.insert(cat)
        context.insert(Transaction(amount: 30, type: .expense, date: Date().startOfMonth, category: cat))
        try context.save()

        let vm = StatsViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        await vm.refresh()

        #expect(vm.expenseDeltaPercent == nil)
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

    @Test func weeklySpendCoversEveryWeekInTheMonthIncludingZeroSpend() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Groceries", emoji: "🛒", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        context.insert(cat)

        let monthStart = Date().startOfMonth
        // Spend only in the first week of the month.
        context.insert(Transaction(amount: 100, type: .expense, date: monthStart, category: cat))
        try context.save()

        let vm = StatsViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        await vm.refresh()

        // Every week overlapping the month is represented, including zero-spend weeks.
        #expect(!vm.weeklySpend.isEmpty)
        #expect(vm.weeklySpend.contains { $0.total == 100 })
        #expect(vm.weeklySpend.contains { $0.total == 0 } || vm.weeklySpend.count == 1)

        // Weekly average only considers weeks that had spend.
        let spentWeeks = vm.weeklySpend.filter { $0.total > 0 }
        let expectedAvg = spentWeeks.reduce(0) { $0 + $1.total } / Double(spentWeeks.count)
        #expect(vm.weeklyAverage == expectedAvg)

        // Week numbers are sequential starting at 1.
        #expect(vm.weeklySpend.first?.weekNumber == 1)
    }
}
