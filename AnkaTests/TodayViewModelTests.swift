import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers `TodayViewModel` aggregation: period filters/navigation (D8),
/// Total-mode hero netting under a category filter (D10), search (incl. tags,
/// AUDIT.md U6), and the per-day total/sign helper used by section headers.
@MainActor
struct TodayViewModelTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    // MARK: - Month navigation

    @Test func navigateMonthSwitchesToMonthModeAndClearsCustomRange() {
        let vm = TodayViewModel()
        vm.selectedPeriod = .custom
        vm.customStartDate = .now
        vm.customEndDate = .now

        vm.navigateMonth(by: 1)

        #expect(vm.selectedPeriod == .month)
        #expect(vm.customStartDate == nil)
        #expect(vm.customEndDate == nil)
        let expected = Date().startOfMonth.addingMonths(1)
        #expect(vm.selectedMonth == expected)
    }

    @Test func jumpToMonthAndResetToCurrentMonth() {
        let vm = TodayViewModel()
        let target = Date().addingMonths(-3)

        vm.jumpToMonth(target)
        #expect(vm.selectedPeriod == .month)
        #expect(vm.selectedMonth == target.startOfMonth)
        #expect(!vm.isViewingCurrentMonth)

        vm.resetToCurrentMonth()
        #expect(vm.isViewingCurrentMonth)
        #expect(vm.selectedMonth == Date().startOfMonth)
    }

    // MARK: - Period interval (D8 half-open)

    @Test func monthPeriodIntervalIsHalfOpen() {
        let vm = TodayViewModel()
        vm.selectedPeriod = .month
        vm.selectedMonth = Date().startOfMonth

        let interval = vm.periodInterval
        #expect(interval.start == Date().startOfMonth)
        #expect(interval.end == Date().startOfMonth.startOfNextMonth)
        // The exclusive end instant belongs to next month, not this one.
        #expect(!interval.containsHalfOpen(interval.end))
        #expect(interval.containsHalfOpen(interval.start))
    }

    @Test func customPeriodIntervalCoversWholeEndDay() {
        let vm = TodayViewModel()
        vm.selectedPeriod = .custom
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = start.addingDays(2)
        vm.customStartDate = start
        vm.customEndDate = end

        let interval = vm.periodInterval
        #expect(interval.start == start)
        #expect(interval.end == end.addingDays(1))
        // A transaction late on the end day still counts.
        let lateOnEndDay = end.addingTimeInterval(23 * 3600)
        #expect(interval.containsHalfOpen(lateOnEndDay))
    }

    // MARK: - heroAmount netting (D10)

    @Test func heroAmountNetsIncomeAndExpenseInTotalModeWithCategoryFilter() async throws {
        let context = try makeContext()
        let foodCat = Anka.Category(name: "Groceries", emoji: "🛒", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        context.insert(foodCat)

        let now = Date()
        context.insert(Transaction(amount: 100, type: .expense, date: now, category: foodCat))
        context.insert(Transaction(amount: 40, type: .income, date: now, category: foodCat))
        try context.save()

        let vm = TodayViewModel()
        let txs = try context.fetch(FetchDescriptor<Transaction>())
        vm.update(transactions: txs, categories: [foodCat])
        vm.selectedPeriod = .month
        vm.selectedMonth = now.startOfMonth
        vm.balanceMode = .total
        vm.selectedCategories = [foodCat]

        await vm.refreshDashboard()

        // Net (income − expense) = 40 − 100 = -60, NOT a sum of 140 (D10 bug).
        #expect(vm.heroAmount == -60)
    }

    @Test func heroAmountSumsFilteredTransactionsInExpenseMode() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Coffee", emoji: "☕", colorHex: "FF8A65", type: .expense, sortOrder: 0)
        context.insert(cat)
        let now = Date()
        context.insert(Transaction(amount: 30, type: .expense, date: now, category: cat))
        context.insert(Transaction(amount: 20, type: .expense, date: now, category: cat))
        try context.save()

        let vm = TodayViewModel()
        let txs = try context.fetch(FetchDescriptor<Transaction>())
        vm.update(transactions: txs, categories: [cat])
        vm.selectedPeriod = .month
        vm.selectedMonth = now.startOfMonth
        vm.balanceMode = .expense
        vm.selectedCategories = [cat]

        await vm.refreshDashboard()

        #expect(vm.heroAmount == 50)
    }

    // MARK: - refreshDashboard grouping

    @Test func refreshDashboardGroupsByDayAndSortsDescending() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Groceries", emoji: "🛒", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        context.insert(cat)

        let now = Date()
        let today = now
        let yesterday = now.addingDays(-1)
        context.insert(Transaction(amount: 10, type: .expense, date: today, note: "today A", category: cat))
        context.insert(Transaction(amount: 20, type: .expense, date: today, note: "today B", category: cat))
        context.insert(Transaction(amount: 30, type: .expense, date: yesterday, note: "yesterday", category: cat))
        try context.save()

        let vm = TodayViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        vm.selectedPeriod = .month
        vm.selectedMonth = now.startOfMonth

        await vm.refreshDashboard()

        #expect(vm.groupedByDay.count == 2)
        // Most recent day first.
        #expect(vm.groupedByDay.first?.date == Calendar.current.startOfDay(for: today))
        #expect(vm.groupedByDay.first?.transactions.count == 2)
        #expect(vm.groupedByDay.last?.transactions.count == 1)
        #expect(vm.expenseTotal == 60)
    }

    @Test func boundaryTransactionAtStartOfNextMonthIsExcluded() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Home", emoji: "🏠", colorHex: "7E57C2", type: .expense, sortOrder: 0)
        context.insert(cat)

        let monthStart = Date().startOfMonth
        let nextMonthStart = monthStart.startOfNextMonth
        context.insert(Transaction(amount: 100, type: .expense, date: monthStart, category: cat))
        context.insert(Transaction(amount: 200, type: .expense, date: nextMonthStart, category: cat))
        try context.save()

        let vm = TodayViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        vm.selectedPeriod = .month
        vm.selectedMonth = monthStart

        await vm.refreshDashboard()

        // Only the transaction exactly at monthStart belongs to this month;
        // the one at the exclusive end (next month's start) does not (D8).
        #expect(vm.expenseTotal == 100)
    }

    // MARK: - Search (U6: tags included)

    @Test func searchMatchesNoteCategoryAndTags() async throws {
        let context = try makeContext()
        let cat = Anka.Category(name: "Coffee", emoji: "☕", colorHex: "FF8A65", type: .expense, sortOrder: 0)
        context.insert(cat)
        let now = Date()
        context.insert(Transaction(amount: 30, type: .expense, date: now, note: "Latte", category: cat, tags: ["work"]))
        context.insert(Transaction(amount: 45, type: .expense, date: now, note: "Lunch", category: cat, tags: ["personal"]))
        try context.save()

        let vm = TodayViewModel()
        vm.update(transactions: try context.fetch(FetchDescriptor<Transaction>()), categories: [cat])
        vm.selectedPeriod = .month
        vm.selectedMonth = now.startOfMonth
        await vm.refreshDashboard()

        // Note match.
        vm.searchQuery = "latte"
        #expect(vm.isSearchActive)
        let noteMatches = vm.displayedGroupedByDay.flatMap(\.transactions)
        #expect(noteMatches.count == 1)
        #expect(noteMatches.first?.note == "Latte")

        // Tag match (AUDIT.md U6).
        vm.searchQuery = "personal"
        let tagMatches = vm.displayedGroupedByDay.flatMap(\.transactions)
        #expect(tagMatches.count == 1)
        #expect(tagMatches.first?.note == "Lunch")

        // No match.
        vm.searchQuery = "nonexistent"
        #expect(vm.displayedGroupedByDay.isEmpty)

        // Clearing search restores the full grouped list.
        vm.clearSearch()
        #expect(!vm.isSearchActive)
        #expect(vm.displayedGroupedByDay.count == vm.groupedByDay.count)
    }

    // MARK: - dailyTotal helper

    @Test func dailyTotalRespectsBalanceMode() {
        let vm = TodayViewModel()
        let cat = Anka.Category(name: "Salary", emoji: "💼", colorHex: "66BB6A", type: .income, sortOrder: 0)
        let income = Transaction(amount: 100, type: .income, category: cat)
        let expense = Transaction(amount: 40, type: .expense, category: cat)

        vm.balanceMode = .expense
        #expect(vm.dailyTotal(for: [expense]).amount == 40)
        #expect(vm.dailyTotal(for: [expense]).sign == "")

        vm.balanceMode = .income
        #expect(vm.dailyTotal(for: [income]).amount == 100)
        #expect(vm.dailyTotal(for: [income]).sign == "+")

        vm.balanceMode = .total
        let (amount, sign) = vm.dailyTotal(for: [income, expense])
        #expect(amount == 60)
        #expect(sign == "+")

        let (negAmount, negSign) = vm.dailyTotal(for: [expense, expense])
        #expect(negAmount == 80)
        #expect(negSign == "-")
    }
}
