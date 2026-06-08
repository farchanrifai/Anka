import Foundation
import SwiftData

// MARK: - Backup payload

/// The top-level JSON document produced by BackupService.export.
/// `version` increments whenever the schema changes in a breaking way;
/// restoring a backup with version > currentVersion emits a warning but
/// still attempts a best-effort import.
struct AnkaBackup: Codable {

    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let transactions: [BackupTransaction]

    struct BackupTransaction: Codable {
        /// Original Transaction.id — used for duplicate detection on restore.
        let id: String
        let amount: Double
        let type: TransactionType
        let categoryName: String?
        let date: Date
        let note: String?
        let currencyCode: String?
        let tags: [String]?
        let paymentMethod: String?
    }
}

// MARK: - Import result

struct BackupImportResult {
    let imported: Int
    let skipped: Int
    let updated: Int
    let deleted: Int
    let warnings: [String]
}

// MARK: - Service

enum BackupService {

    // MARK: - Export

    /// Encodes the given transactions as a versioned JSON payload.
    static func export(transactions: [Transaction]) throws -> Data {
        let backupTxns = transactions.map { tx in
            AnkaBackup.BackupTransaction(
                id: tx.id.uuidString,
                amount: tx.amount,
                type: tx.type,
                categoryName: tx.category?.name,
                date: tx.date,
                note: tx.note,
                currencyCode: tx.currencyCode,
                tags: tx.tags.isEmpty ? nil : tx.tags,
                paymentMethod: tx.paymentMethod
            )
        }
        let backup = AnkaBackup(
            version: AnkaBackup.currentVersion,
            exportedAt: Date(),
            transactions: backupTxns
        )
        return try Self.encoder.encode(backup)
    }

    // MARK: - Restore

    /// Reads a JSON file at `url`, imports non-duplicate transactions into `context`,
    /// and returns a result describing what was imported, skipped, and any warnings.
    ///
    /// Duplicate detection uses the transaction's original UUID so that re-importing
    /// the same backup file is always idempotent.
    @discardableResult
    static func restore(
        from url: URL,
        into context: ModelContext,
        replaceExisting: Bool = false
    ) throws -> BackupImportResult {
        let data = try Data(contentsOf: url)
        let backup = try Self.decoder.decode(AnkaBackup.self, from: data)

        // Version gate
        var warnings: [String] = []
        if backup.version > AnkaBackup.currentVersion {
            warnings.append(
                "This backup was created with a newer version of Anka (v\(backup.version)). " +
                "Some data may not be fully restored."
            )
        }

        let existingTxns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let existingTxnsById = Dictionary(existingTxns.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })

        // Cache existing categories to avoid redundant fetches
        let allCats     = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var catsByName  = Dictionary(allCats.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var imported = 0
        var skipped  = 0
        var updated  = 0
        var deleted  = 0

        let backupIDs = Set(backup.transactions.map(\.id))

        if replaceExisting {
            // Delete any local transaction that is not in the backup
            for tx in existingTxns {
                if !backupIDs.contains(tx.id.uuidString) {
                    context.delete(tx)
                    deleted += 1
                }
            }
        }

        for btx in backup.transactions {
            if let existing = existingTxnsById[btx.id] {
                if replaceExisting {
                    // Update existing transaction
                    existing.amount = btx.amount
                    existing.type = btx.type
                    existing.date = btx.date
                    existing.note = btx.note
                    existing.currencyCode = btx.currencyCode ?? "USD"
                    existing.tags = btx.tags ?? []
                    existing.paymentMethod = btx.paymentMethod

                    // Resolve category
                    existing.category = resolveCategory(
                        name: btx.categoryName, cache: &catsByName, context: context)
                    updated += 1
                } else {
                    skipped += 1
                }
                continue
            }

            // Resolve or lazily create the category
            let category = resolveCategory(
                name: btx.categoryName, cache: &catsByName, context: context)

            let tx = Transaction(
                id: UUID(uuidString: btx.id) ?? UUID(),
                amount: btx.amount,
                type: btx.type,
                date: btx.date,
                note: btx.note,
                category: category,
                currencyCode: btx.currencyCode ?? "USD",
                tags: btx.tags ?? [],
                paymentMethod: btx.paymentMethod
            )
            context.insert(tx)
            imported += 1
        }

        try context.save()
        return BackupImportResult(imported: imported, skipped: skipped, updated: updated, deleted: deleted, warnings: warnings)
    }

    // MARK: - Restore (async with progress)

    enum RestorePhase: Sendable {
        case reading
        case processing(done: Int, total: Int)
        case saving
    }

    /// Async variant of `restore` that periodically yields to the runloop and
    /// reports progress through a callback. Use this from UI code so the
    /// progress bar updates and the app doesn't appear frozen during long
    /// restores.
    @MainActor
    @discardableResult
    static func restore(
        from url: URL,
        into context: ModelContext,
        replaceExisting: Bool = false,
        progress: @MainActor (RestorePhase) -> Void
    ) async throws -> BackupImportResult {
        progress(.reading)
        await Task.yield()

        let data = try Data(contentsOf: url)
        let backup = try Self.decoder.decode(AnkaBackup.self, from: data)

        var warnings: [String] = []
        if backup.version > AnkaBackup.currentVersion {
            warnings.append(
                "This backup was created with a newer version of Anka (v\(backup.version)). " +
                "Some data may not be fully restored."
            )
        }

        let existingTxns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let existingTxnsById = Dictionary(existingTxns.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let allCats     = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var catsByName  = Dictionary(allCats.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var imported = 0, skipped = 0, updated = 0, deleted = 0
        let total = backup.transactions.count
        let backupIDs = Set(backup.transactions.map(\.id))

        progress(.processing(done: 0, total: total))
        await Task.yield()

        if replaceExisting {
            for tx in existingTxns where !backupIDs.contains(tx.id.uuidString) {
                context.delete(tx)
                deleted += 1
            }
        }

        let yieldEvery = 100
        for (index, btx) in backup.transactions.enumerated() {
            if let existing = existingTxnsById[btx.id] {
                if replaceExisting {
                    existing.amount = btx.amount
                    existing.type = btx.type
                    existing.date = btx.date
                    existing.note = btx.note
                    existing.currencyCode = btx.currencyCode ?? "USD"
                    existing.tags = btx.tags ?? []
                    existing.paymentMethod = btx.paymentMethod
                    existing.category = resolveCategory(
                        name: btx.categoryName, cache: &catsByName, context: context)
                    updated += 1
                } else {
                    skipped += 1
                }
            } else {
                let category = resolveCategory(
                    name: btx.categoryName, cache: &catsByName, context: context)
                let tx = Transaction(
                    id: UUID(uuidString: btx.id) ?? UUID(),
                    amount: btx.amount,
                    type: btx.type,
                    date: btx.date,
                    note: btx.note,
                    category: category,
                    currencyCode: btx.currencyCode ?? "USD",
                    tags: btx.tags ?? [],
                    paymentMethod: btx.paymentMethod
                )
                context.insert(tx)
                imported += 1
            }

            if (index + 1) % yieldEvery == 0 {
                progress(.processing(done: index + 1, total: total))
                await Task.yield()
            }
        }

        progress(.saving)
        await Task.yield()
        try context.save()

        return BackupImportResult(imported: imported, skipped: skipped, updated: updated, deleted: deleted, warnings: warnings)
    }

    @MainActor
    private static func resolveCategory(
        name: String?,
        cache: inout [String: Category],
        context: ModelContext
    ) -> Category? {
        guard let name, !name.isEmpty else { return nil }
        let key = name.lowercased()
        if let existing = cache[key] { return existing }
        let newCat = Category(name: name, emoji: "📦", colorHex: "#9E9E9E", type: .expense, sortOrder: 999)
        context.insert(newCat)
        cache[key] = newCat
        return newCat
    }

    // MARK: - Shared codec

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting     = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
