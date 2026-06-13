import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers the Batch 2 backup-v2 work (AUDIT.md D3/D4/A3): category metadata
/// survives a restore, v1 files still decode, merge dedupes by UUID, and
/// replace deletes local rows missing from the backup.
@MainActor
struct BackupServiceTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    private func fetchTxns(_ ctx: ModelContext) -> [Transaction] {
        (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    private func fetchCats(_ ctx: ModelContext) -> [Anka.Category] {
        (try? ctx.fetch(FetchDescriptor<Anka.Category>())) ?? []
    }

    private func writeTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-backup-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @discardableResult
    private func restore(_ url: URL, into ctx: ModelContext, replaceExisting: Bool = false) async throws -> BackupImportResult {
        try await BackupService.restore(from: url, into: ctx, replaceExisting: replaceExisting) { _ in }
    }

    // MARK: - v2 round-trip preserves category metadata (D3)

    @Test func v2RestorePreservesIncomeCategoryType() async throws {
        // Source: one income category + a matching income transaction.
        let source = try makeContext()
        let salary = Anka.Category(name: "Salary", emoji: "💼", colorHex: "66BB6A", type: .income, sortOrder: 0)
        source.insert(salary)
        source.insert(Transaction(amount: 5_000_000, type: .income, note: "May pay", category: salary))
        try source.save()

        let data = try BackupService.export(
            transactions: fetchTxns(source), categories: fetchCats(source)
        )
        let url = try writeTemp(data)

        // Restore into an empty store.
        let dest = try makeContext()
        let result = try await restore(url, into: dest)

        #expect(result.imported == 1)
        let cats = fetchCats(dest)
        let restored = try #require(cats.first { $0.name == "Salary" })
        // The bug this guards: a name-only restore recreated everything as .expense.
        #expect(restored.type == .income)
        #expect(restored.emoji == "💼")
        #expect(restored.colorHex == "66BB6A")
        #expect(fetchTxns(dest).first?.type == .income)
        #expect(fetchTxns(dest).first?.category?.name == "Salary")
    }

    // MARK: - v1 file (no categories key) still decodes (A3 back-compat)

    @Test func v1FileDecodesAndUsesTxTypeFallback() async throws {
        // Hand-crafted v1 payload: no `categories`, no currencyCode/tags.
        let id = UUID().uuidString
        let json = """
        {
          "version": 1,
          "exportedAt": 1700000000,
          "transactions": [
            { "id": "\(id)", "amount": 250000, "type": "income",
              "categoryName": "Freelance", "date": 1700000000 }
          ]
        }
        """
        let url = try writeTemp(Data(json.utf8))

        let dest = try makeContext()
        let result = try await restore(url, into: dest)

        #expect(result.imported == 1)
        let cat = try #require(fetchCats(dest).first { $0.name == "Freelance" })
        // No metadata in a v1 file → category type falls back to the tx type,
        // so an income row can't spawn an expense category (D3/D4).
        #expect(cat.type == .income)
        let tx = try #require(fetchTxns(dest).first)
        // Missing currencyCode defaults to the app currency, not "USD" (D4).
        #expect(tx.currencyCode == AppCurrency.code)
    }

    // MARK: - Merge dedupes by UUID (idempotent re-import)

    @Test func mergeSkipsDuplicatesByID() async throws {
        let source = try makeContext()
        let cat = Anka.Category(name: "Coffee", emoji: "☕", colorHex: "FF8A65", type: .expense, sortOrder: 0)
        source.insert(cat)
        source.insert(Transaction(amount: 30_000, type: .expense, note: "Latte", category: cat))
        source.insert(Transaction(amount: 45_000, type: .expense, note: "Lunch", category: cat))
        try source.save()
        let url = try writeTemp(try BackupService.export(
            transactions: fetchTxns(source), categories: fetchCats(source)))

        let dest = try makeContext()
        let first = try await restore(url, into: dest)
        #expect(first.imported == 2)

        // Re-importing the same file imports nothing new.
        let second = try await restore(url, into: dest)
        #expect(second.imported == 0)
        #expect(second.skipped == 2)
        #expect(fetchTxns(dest).count == 2)
    }

    // MARK: - Replace deletes local rows missing from the backup

    @Test func replaceDeletesRowsNotInBackup() async throws {
        let source = try makeContext()
        let cat = Anka.Category(name: "Taxi", emoji: "🚕", colorHex: "42A5F5", type: .expense, sortOrder: 0)
        source.insert(cat)
        source.insert(Transaction(amount: 20_000, type: .expense, note: "Ride", category: cat))
        try source.save()
        let url = try writeTemp(try BackupService.export(
            transactions: fetchTxns(source), categories: fetchCats(source)))

        // Dest has an unrelated local transaction not present in the backup.
        let dest = try makeContext()
        dest.insert(Transaction(amount: 99_000, type: .expense, note: "Local only"))
        try dest.save()

        let result = try await restore(url, into: dest, replaceExisting: true)
        #expect(result.deleted == 1)
        #expect(result.imported == 1)
        let notes = Set(fetchTxns(dest).compactMap(\.note))
        #expect(notes == ["Ride"])
    }
}
