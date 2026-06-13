import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers the Phase 8.5 inline natural-language parser: amount/note/date
/// extraction and category detection (via the existing keyword/ML predictor).
@MainActor
struct InlineTransactionParserTests {

    private let parser = InlineTransactionParser()

    /// Default expense + income categories, materialised in an in-memory store
    /// so name-based category matching has something to resolve against.
    private func defaultCategories() throws -> [Anka.Category] {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        let ctx = ModelContext(container)
        let cats = SampleData.createDefaultCategories()
        for c in cats { ctx.insert(c) }
        try ctx.save()
        return cats
    }

    private func todayStart() -> Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: - Amount + category + note + date

    @Test func parsesAmountCategoryNoteToday() throws {
        let cats = try defaultCategories()
        let result = parser.parse("5k for coffee", availableCategories: cats, predictor: CategoryPredictor())
        let r = try #require(result)
        #expect(r.amount == 5000)
        #expect(r.note == "coffee")
        #expect(r.category?.name == "Coffee")
        #expect(Calendar.current.isDateInToday(r.date))
        #expect(r.confidence == 1.0)
    }

    @Test func parsesAmountAndYesterday() throws {
        let cats = try defaultCategories()
        let result = parser.parse("100k grabfood yesterday", availableCategories: cats, predictor: CategoryPredictor())
        let r = try #require(result)
        #expect(r.amount == 100_000)
        #expect(r.note == "grabfood")
        #expect(r.category?.name == "Food Delivery")
        #expect(Calendar.current.isDateInYesterday(r.date))
    }

    @Test func amountWithNoCategoryHasHalfConfidence() throws {
        let cats = try defaultCategories()
        // "qwerty" matches no keyword/category → amount only.
        let result = parser.parse("50000 qwerty", availableCategories: cats, predictor: CategoryPredictor())
        let r = try #require(result)
        #expect(r.amount == 50_000)
        #expect(r.category == nil)
        #expect(r.confidence == 0.5)
    }

    @Test func noAmountReturnsNil() throws {
        let cats = try defaultCategories()
        #expect(parser.parse("coffee", availableCategories: cats, predictor: CategoryPredictor()) == nil)
        #expect(parser.parse("   ", availableCategories: cats, predictor: CategoryPredictor()) == nil)
    }

    // MARK: - Relative date extraction (pure, no predictor)

    @Test func extractsYesterday() {
        let (date, remainder) = parser.extractDate(from: "100k grabfood yesterday")
        #expect(Calendar.current.isDateInYesterday(date))
        #expect(!remainder.lowercased().contains("yesterday"))
        #expect(remainder.contains("grabfood"))
    }

    @Test func extractsTomorrow() {
        let (date, _) = parser.extractDate(from: "20k snacks tomorrow")
        #expect(Calendar.current.isDateInTomorrow(date))
    }

    @Test func extractsNDaysAgo() {
        let (date, remainder) = parser.extractDate(from: "30k lunch 3 days ago")
        let expected = Calendar.current.date(byAdding: .day, value: -3, to: todayStart())
        #expect(Calendar.current.isDate(date, inSameDayAs: expected ?? Date()))
        #expect(!remainder.contains("3 days ago"))
    }

    @Test func extractsNDaysFromNow() {
        let (date, _) = parser.extractDate(from: "rent 5 days from now")
        let expected = Calendar.current.date(byAdding: .day, value: 5, to: todayStart())
        #expect(Calendar.current.isDate(date, inSameDayAs: expected ?? Date()))
    }

    @Test func noDateDefaultsToToday() {
        let (date, remainder) = parser.extractDate(from: "5k coffee")
        #expect(Calendar.current.isDateInToday(date))
        #expect(remainder == "5k coffee")
    }
}
