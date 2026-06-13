import Testing
import Foundation
import SwiftData
@testable import Anka

/// Covers `AnkaApp.seedOrMigrateCategories` (the one-time Phase 5 → ML
/// taxonomy migration): fresh-install seeding, migrating the old taxonomy
/// while preserving transactions as "Uncategorized", and idempotency.
struct CategoryMigrationTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transaction.self, Anka.Category.self, configurations: config)
        return ModelContext(container)
    }

    /// Each test gets its own UserDefaults suite so the migration flag
    /// doesn't leak between tests (or from a real run on this machine).
    private func makeDefaults() -> UserDefaults {
        let suite = "CategoryMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func fetchCats(_ ctx: ModelContext) throws -> [Anka.Category] {
        try ctx.fetch(FetchDescriptor<Anka.Category>())
    }

    @Test func freshInstallSeedsDefaultTaxonomy() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        AnkaApp.seedOrMigrateCategories(in: context, defaults: defaults)

        let cats = try fetchCats(context)
        #expect(cats.count == SampleData.createDefaultCategories().count)
        #expect(cats.contains { $0.name == "Groceries" })
        #expect(defaults.bool(forKey: AnkaApp.categoryMigrationKey))
    }

    @Test func oldTaxonomyIsMigratedAndTransactionsPreserved() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        // Simulate a pre-ML install: old "Food & Dining" category with a
        // linked transaction, migration flag not yet set.
        let oldFood = Anka.Category(name: "Food & Dining", emoji: "🍔", colorHex: "FF6B6B", type: .expense, sortOrder: 0)
        context.insert(oldFood)
        let tx = Transaction(amount: 25_000, type: .expense, note: "Old lunch", category: oldFood)
        context.insert(tx)
        try context.save()

        AnkaApp.seedOrMigrateCategories(in: context, defaults: defaults)

        let cats = try fetchCats(context)
        // Old taxonomy name is gone.
        #expect(!cats.contains { $0.name == "Food & Dining" })
        // New ML-aligned defaults are present.
        #expect(cats.contains { $0.name == "Eating Out" })
        #expect(cats.contains { $0.name == "Groceries" })

        // The transaction survives, unlinked rather than cascade-deleted (D1).
        let txs = try context.fetch(FetchDescriptor<Transaction>())
        #expect(txs.count == 1)
        #expect(txs.first?.note == "Old lunch")
        #expect(txs.first?.category == nil)

        #expect(defaults.bool(forKey: AnkaApp.categoryMigrationKey))
    }

    @Test func migrationDoesNotRunTwice() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        // First run: fresh install seeds defaults and sets the flag.
        AnkaApp.seedOrMigrateCategories(in: context, defaults: defaults)
        let firstCount = try fetchCats(context).count

        // Second run is a no-op even if old-taxonomy names are (re)introduced.
        context.insert(Anka.Category(name: "Food & Dining", emoji: "🍔", colorHex: "FF6B6B", type: .expense, sortOrder: 99))
        try context.save()

        AnkaApp.seedOrMigrateCategories(in: context, defaults: defaults)

        let cats = try fetchCats(context)
        // The migration didn't touch anything — both the original seed set
        // and the manually-added "Food & Dining" remain.
        #expect(cats.count == firstCount + 1)
        #expect(cats.contains { $0.name == "Food & Dining" })
    }

    @Test func curatedInstallWithoutOldNamesIsLeftAlone() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        // A user who already curated categories with none of the old names —
        // migration should just flag done without altering anything.
        let custom = Anka.Category(name: "My Custom Cat", emoji: "✨", colorHex: "F26666", type: .expense, sortOrder: 0)
        context.insert(custom)
        try context.save()

        AnkaApp.seedOrMigrateCategories(in: context, defaults: defaults)

        let cats = try fetchCats(context)
        #expect(cats.count == 1)
        #expect(cats.first?.name == "My Custom Cat")
        #expect(defaults.bool(forKey: AnkaApp.categoryMigrationKey))
    }
}
