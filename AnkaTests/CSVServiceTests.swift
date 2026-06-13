import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers the Batch 4 CSV work (AUDIT.md D7/D9): the tokenizer handles quoted
/// commas / newlines / escaped quotes, export→import round-trips special
/// characters, and the preview flags duplicates of existing data.
@MainActor
struct CSVServiceTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    private func writeTemp(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tokenizer (D7)

    @Test func parsesQuotedCommaAndEscapedQuote() {
        let rows = CSVService.parseCSV(#"a,"b,c","he said ""hi""",d"#)
        #expect(rows.count == 1)
        #expect(rows[0] == ["a", "b,c", #"he said "hi""#, "d"])
    }

    @Test func parsesQuotedNewline() {
        // A quoted field containing a newline must NOT split into two rows.
        let csv = "h1,h2\n\"line1\nline2\",x\n"
        let rows = CSVService.parseCSV(csv)
        #expect(rows.count == 2)
        #expect(rows[1] == ["line1\nline2", "x"])
    }

    @Test func handlesCRLFAndTrailingNewline() {
        let rows = CSVService.parseCSV("a,b\r\nc,d\r\n")
        #expect(rows == [["a", "b"], ["c", "d"]])
    }

    // MARK: - Round-trip (D7)

    @Test func roundTripPreservesSpecialCharacters() throws {
        let ctx = try makeContext()
        let cat = Anka.Category(name: "Eating Out", emoji: "🍽️", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        ctx.insert(cat)
        let trickyNote = #"He said "hi", then left"#
        ctx.insert(Transaction(amount: 42_000, type: .expense, note: trickyNote, category: cat))
        try ctx.save()

        let txns = (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
        let csv = CSVService.export(txns)
        let url = try writeTemp(csv)

        let preview = try CSVService.parsePreview(from: url, availableCategories: [cat])
        #expect(preview.parseErrors.isEmpty)
        #expect(preview.transactions.count == 1)
        // The comma + embedded quotes survive the escape/unescape round-trip.
        #expect(preview.transactions.first?.note == trickyNote)
        #expect(preview.transactions.first?.matchedCategory?.name == "Eating Out")
    }

    // MARK: - Duplicate detection (D9)

    @Test func flagsDuplicatesOfExistingData() throws {
        let ctx = try makeContext()
        // Build the existing tx's date via the same date-only pipeline the CSV
        // uses, so the day-granular signature matches regardless of time zone.
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
        let day = try #require(iso.date(from: "2026-03-15"))

        let existing = Transaction(amount: 30_000, type: .expense, date: day, note: "Latte")
        ctx.insert(existing)
        try ctx.save()

        // Export it, then re-import with the same data present.
        let csv = CSVService.export([existing])
        let url = try writeTemp(csv)

        let preview = try CSVService.parsePreview(
            from: url, availableCategories: [], existingTransactions: [existing]
        )
        #expect(preview.transactions.count == 1)
        #expect(preview.duplicateCount == 1)
        #expect(preview.transactions.first?.isDuplicate == true)
    }

    @Test func newRowsAreNotFlaggedAsDuplicates() throws {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
        let day = try #require(iso.date(from: "2026-03-15"))
        let existing = Transaction(amount: 30_000, type: .expense, date: day, note: "Latte")

        // CSV row for a *different* amount → not a duplicate.
        let csv = "date,type,amount,note\n2026-03-15,expense,99000,Dinner\n"
        let url = try writeTemp(csv)

        let preview = try CSVService.parsePreview(
            from: url, availableCategories: [], existingTransactions: [existing]
        )
        #expect(preview.transactions.count == 1)
        #expect(preview.duplicateCount == 0)
    }
}
