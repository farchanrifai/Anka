import Foundation
import SwiftData

// MARK: - Backup payload

/// The top-level JSON document produced by BackupService.export.
/// `version` increments whenever the schema changes in a breaking way;
/// restoring a backup with version > currentVersion emits a warning but
/// still attempts a best-effort import.
struct AnkaBackup: Codable {

    /// v1 — transactions only (category stored as a bare name).
    /// v2 — adds `categories` so emoji / color / **type** / order survive a
    ///      restore onto a fresh install (see AUDIT.md D3). v1 files still
    ///      decode: `categories` is optional and absent → name-only fallback.
    static let currentVersion = 2

    let version: Int
    let exportedAt: Date
    let transactions: [BackupTransaction]
    /// Optional so v1 payloads (no categories key) still decode.
    let categories: [BackupCategory]?

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

    struct BackupCategory: Codable {
        let name: String
        let emoji: String
        let colorHex: String
        let type: TransactionType
        let sortOrder: Int
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

    /// Encodes the given transactions + categories as a versioned JSON payload.
    static func export(transactions: [Transaction], categories: [Category]) throws -> Data {
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
        let backupCats = categories.map { cat in
            AnkaBackup.BackupCategory(
                name: cat.name,
                emoji: cat.emoji,
                colorHex: cat.colorHex,
                type: cat.type,
                sortOrder: cat.sortOrder
            )
        }
        let backup = AnkaBackup(
            version: AnkaBackup.currentVersion,
            exportedAt: Date(),
            transactions: backupTxns,
            categories: backupCats
        )
        return try Self.encoder.encode(backup)
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

        // v2: metadata for the backup's categories, keyed by lowercased name.
        // Drives both the pre-pass (recreate missing categories with the right
        // type/emoji/color/order) and the per-transaction fallback below. v1
        // payloads have no `categories` → empty map → name-only behavior.
        let backupCatMeta: [String: AnkaBackup.BackupCategory] = Dictionary(
            (backup.categories ?? []).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Pre-pass: ensure every category named in the backup exists locally,
        // created with its real metadata. Fixes AUDIT.md D3 (income categories
        // were previously recreated as expenses).
        for meta in backup.categories ?? [] {
            let key = meta.name.lowercased()
            guard catsByName[key] == nil else { continue }
            let cat = Category(
                name: meta.name,
                emoji: meta.emoji,
                colorHex: meta.colorHex,
                type: meta.type,
                sortOrder: meta.sortOrder
            )
            context.insert(cat)
            catsByName[key] = cat
        }

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
                    existing.currencyCode = btx.currencyCode ?? AppCurrency.code
                    existing.tags = btx.tags ?? []
                    existing.paymentMethod = btx.paymentMethod
                    existing.category = resolveCategory(
                        name: btx.categoryName, fallbackType: btx.type,
                        meta: backupCatMeta, cache: &catsByName, context: context)
                    updated += 1
                } else {
                    skipped += 1
                }
            } else {
                let category = resolveCategory(
                    name: btx.categoryName, fallbackType: btx.type,
                    meta: backupCatMeta, cache: &catsByName, context: context)
                let tx = Transaction(
                    id: UUID(uuidString: btx.id) ?? UUID(),
                    amount: btx.amount,
                    type: btx.type,
                    date: btx.date,
                    note: btx.note,
                    category: category,
                    currencyCode: btx.currencyCode ?? AppCurrency.code,
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
        NotificationCenter.default.post(name: .ankaDataDidChange, object: nil)

        return BackupImportResult(imported: imported, skipped: skipped, updated: updated, deleted: deleted, warnings: warnings)
    }

    /// Resolves the local `Category` for a backup transaction's category name,
    /// creating one lazily if absent. Prefers the backup's own category
    /// metadata (v2); for a v1 file with no metadata, falls back to the
    /// transaction's own type (so an income transaction can't spawn an expense
    /// category — AUDIT.md D3/D4) and a neutral emoji/color.
    @MainActor
    private static func resolveCategory(
        name: String?,
        fallbackType: TransactionType,
        meta: [String: AnkaBackup.BackupCategory],
        cache: inout [String: Category],
        context: ModelContext
    ) -> Category? {
        guard let name, !name.isEmpty else { return nil }
        let key = name.lowercased()
        if let existing = cache[key] { return existing }

        let newCat: Category
        if let m = meta[key] {
            newCat = Category(name: m.name, emoji: m.emoji, colorHex: m.colorHex,
                              type: m.type, sortOrder: m.sortOrder)
        } else {
            newCat = Category(name: name, emoji: "📦", colorHex: "#9E9E9E",
                              type: fallbackType, sortOrder: 999)
        }
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
