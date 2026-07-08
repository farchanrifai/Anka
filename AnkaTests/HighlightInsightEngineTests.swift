import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers the Highlights insight math (Phase 8.7): weekly bar data, monthly
/// per-day averages, daily cumulative tracking, and the top-category
/// breakdown — including the zero-data edges.
@MainActor
struct HighlightInsightEngineTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    // MARK: - Weekly

    @Test func weeklyHighlightBucketsSevenDays() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 100, type: .expense, date: .now))
        context.insert(Transaction(amount: 50, type: .expense, date: .now.addingDays(-1)))
        // Income must not count.
        context.insert(Transaction(amount: 999, type: .income, date: .now))
        // Outside the 7-day window.
        context.insert(Transaction(amount: 777, type: .expense, date: .now.addingDays(-8)))
        try context.save()

        let data = HighlightInsightEngine(modelContext: context).weeklyHighlight()

        #expect(data.days.count == 7)
        #expect(data.days.last?.total == 100)          // today
        #expect(data.days[5].total == 50)              // yesterday
        #expect(data.days.first?.total == 0)           // 6 days ago
        #expect(abs(data.dailyAverage - 150.0 / 7.0) < 0.001)
    }

    @Test func weeklyHighlightZeroDataIsAllZeros() throws {
        let context = try makeContext()
        let data = HighlightInsightEngine(modelContext: context).weeklyHighlight()
        #expect(data.days.allSatisfy { $0.total == 0 })
        #expect(data.dailyAverage == 0)
    }

    // MARK: - Monthly

    @Test func monthlyHighlightAveragesPerDay() throws {
        let context = try makeContext()
        let now = Date()
        context.insert(Transaction(amount: 90, type: .expense, date: now.startOfMonth))
        try context.save()

        let data = HighlightInsightEngine(modelContext: context).monthlyHighlight()

        let daysElapsed = max(1, Calendar.current.component(.day, from: now))
        #expect(abs(data.thisMonthAvgPerDay - 90.0 / Double(daysElapsed)) < 0.001)
        #expect(data.lastMonthAvgPerDay == 0)
        #expect(data.thisMonthLabel == now.startOfMonth.monthName)
    }

    // MARK: - Daily

    @Test func dailyHighlightZeroDataHasNoChart() throws {
        let context = try makeContext()
        let data = HighlightInsightEngine(modelContext: context).dailyHighlight()
        #expect(data.todayTotal == 0)
        #expect(data.averageTotal == 0)
        #expect(data.cumulativeToday.isEmpty)
        #expect(!data.hasEnoughDataForChart)
    }

    @Test func dailyHighlightAccumulatesToday() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 30, type: .expense, date: .now))
        context.insert(Transaction(amount: 20, type: .expense, date: .now))
        // Lookback data so the chart threshold is met.
        context.insert(Transaction(amount: 60, type: .expense, date: .now.addingDays(-2)))
        try context.save()

        let data = HighlightInsightEngine(modelContext: context).dailyHighlight()

        #expect(data.todayTotal == 50)
        #expect(data.cumulativeToday.count == 2)
        #expect(data.cumulativeToday.last?.amount == 50)
        #expect(abs(data.averageTotal - 60.0 / 30.0) < 0.001)  // lookbackDays = 30
        #expect(data.hasEnoughDataForChart)
    }

    // MARK: - Top categories

    @Test func topCategoryHighlightNilWithoutData() throws {
        let context = try makeContext()
        #expect(HighlightInsightEngine(modelContext: context).topCategoryHighlight() == nil)
    }

    @Test func topCategoryHighlightSortsAndCapsAtThree() throws {
        let context = try makeContext()
        let cats = (0..<4).map { i in
            Anka.Category(name: "Cat\(i)", emoji: "🏷️", colorHex: "FF6B6B", type: .expense, sortOrder: i)
        }
        cats.forEach { context.insert($0) }
        // Spend: Cat0=10, Cat1=40, Cat2=20, Cat3=30 this month.
        for (cat, amount) in zip(cats, [10.0, 40, 20, 30]) {
            context.insert(Transaction(amount: amount, type: .expense, date: .now, category: cat))
        }
        try context.save()

        let data = try #require(HighlightInsightEngine(modelContext: context).topCategoryHighlight())

        #expect(data.categories.count == 3)
        #expect(data.categories.map(\.amount) == [40, 30, 20])
        #expect(data.categories.first?.name == "Cat1")
        #expect(data.totalExpense == 100)
    }
}
