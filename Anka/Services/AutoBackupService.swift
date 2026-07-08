import Foundation
import SwiftData

// MARK: - Auto Backup Service
//
// Maintains up to 7 silent JSON backups in two locations:
//   • App Group:  group.com.nc.Anka/Backups/
//   • Documents:  <app>/Documents/Backups/
//
// Triggered after every transaction save/delete (no gate) and on
// app foreground (24-hour gate via shouldBackup()).

@Observable @MainActor
final class AutoBackupService {

    static let shared = AutoBackupService()
    private init() {}

    // MARK: - Public Types

    struct BackupFile: Identifiable, Sendable {
        /// Filename is unique per backup and stable across `listBackups()` calls,
        /// so it's the identity (was a fresh `UUID()` per listing, which
        /// invalidated `txCounts` keyed by it — AUDIT.md A4).
        var id: String { name }
        let name: String       // anka-backup-2026-05-22T14-30-00.json
        let url: URL           // preferred URL: App Group > Documents
        let agURL: URL?        // App Group copy (nil if absent)
        let docsURL: URL?      // Documents copy (nil if absent)
        let createdAt: Date
        let fileSize: Int64

        init(name: String, url: URL, agURL: URL?, docsURL: URL?,
             createdAt: Date, fileSize: Int64) {
            self.name      = name
            self.url       = url
            self.agURL     = agURL
            self.docsURL   = docsURL
            self.createdAt = createdAt
            self.fileSize  = fileSize
        }
    }

    // The on-disk payload is `AnkaBackup` (see BackupService) — auto-backups and
    // manual exports now share one format, so restore reads either. The former
    // private `AnkaAutoBackup` duplicate + its own encoder are gone (AUDIT.md A3).

    // MARK: - Constants

    private static let maxBackups     = 7
    /// UserDefaults key for the last-backup timestamp. Exposed so the Backup
    /// screen reads the same key instead of re-typing the string literal.
    static let lastBackupKey  = "autoBackupLastDate"
    private static let backupInterval: TimeInterval = 24 * 3600

    // MARK: - Automatic triggers
    //
    // These are the entry points that make auto-backup actually automatic
    // (see AUDIT.md D2 — previously `performBackup` was only ever called by the
    // manual "Back Up Now" button and `shouldBackup()` was dead code).

    /// Called on app foreground. Backs up only when more than 24h have passed
    /// since the last backup, so normal launches don't thrash the disk.
    func backupOnForegroundIfNeeded(transactions: [Transaction], categories: [Category]) {
        guard shouldBackup() else { return }
        let txs = transactions, cats = categories
        Task { await performBackup(transactions: txs, categories: cats) }
    }

    /// Called after a transaction is saved, deleted, imported, or restored.
    /// Snapshots the current state, throttled to at most once per
    /// `minChangeInterval` so a bulk edit/import doesn't evict the rolling
    /// 7-backup history within a single burst.
    private static let minChangeInterval: TimeInterval = 120
    func backupAfterChange(transactions: [Transaction], categories: [Category]) {
        let last = UserDefaults.standard.double(forKey: Self.lastBackupKey)
        if last > 0, Date().timeIntervalSince1970 - last < Self.minChangeInterval { return }
        let txs = transactions, cats = categories
        Task { await performBackup(transactions: txs, categories: cats) }
    }

    // MARK: - Perform Backup

    func performBackup(
        transactions: [Transaction],
        categories: [Category]
    ) async {
        // 1. DTO mapping on MainActor (safe — @Model objects live here); the
        //    JSON encoding itself runs in the detached write task below. Shares
        //    the versioned AnkaBackup format (v2: includes categories) with
        //    manual exports, so any backup file restores through the same path.
        let liveTxns = transactions.filter { !$0.isDeleted }
        let backup = BackupService.makeBackup(transactions: liveTxns, categories: categories)

        // 2. Resolve target directories (URL and AnkaBackup are Sendable value types)
        let fm       = FileManager.default
        let agDir    = fm.containerURL(forSecurityApplicationGroupIdentifier: PlatformPaths.appGroupID)?
                          .appendingPathComponent("Backups")
        let docsDir  = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
                          .appendingPathComponent("Backups")
        let filename = Self.makeFilename()
        let agFile   = agDir?.appendingPathComponent(filename)
        let docsFile = docsDir?.appendingPathComponent(filename)

        // 3. Encode once + write both targets in a detached background task
        await Task.detached(priority: .background) {
            guard let data = try? BackupService.encode(backup) else { return }
            for (dir, file) in [(agDir, agFile), (docsDir, docsFile)] {
                guard let dir, let file else { continue }
                try? FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
        }.value

        // 4. Prune old backups
        if let dir = agDir   { pruneOldBackups(in: dir) }
        if let dir = docsDir { pruneOldBackups(in: dir) }

        // 5. Record timestamp for shouldBackup() gate
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: Self.lastBackupKey)
    }

    // MARK: - 24-Hour Gate

    func shouldBackup() -> Bool {
        let last = UserDefaults.standard.double(forKey: Self.lastBackupKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last > Self.backupInterval
    }

    // MARK: - List Backups

    func listBackups() -> [BackupFile] {
        let fm = FileManager.default
        let agDir = fm.containerURL(
            forSecurityApplicationGroupIdentifier: PlatformPaths.appGroupID)?
            .appendingPathComponent("Backups")
        let docsDir = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
            .appendingPathComponent("Backups")

        func index(_ dir: URL?) -> [String: URL] {
            guard let dir else { return [:] }
            let files = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles)) ?? []
            return Dictionary(uniqueKeysWithValues:
                files
                    .filter {
                        $0.lastPathComponent.hasPrefix("anka-backup-") &&
                        $0.pathExtension == "json"
                    }
                    .map { ($0.lastPathComponent, $0) }
            )
        }

        let agFiles   = index(agDir)
        let docsFiles = index(docsDir)
        let allNames  = Set(agFiles.keys).union(docsFiles.keys)

        return allNames.compactMap { name -> BackupFile? in
            let ag   = agFiles[name]
            let docs = docsFiles[name]
            guard let url = ag ?? docs else { return nil }
            let res       = try? url.resourceValues(
                forKeys: [.creationDateKey, .fileSizeKey])
            return BackupFile(
                name:      name,
                url:       url,
                agURL:     ag,
                docsURL:   docs,
                createdAt: res?.creationDate ?? .distantPast,
                fileSize:  Int64(res?.fileSize ?? 0)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Transaction Count (partial decode — no full object allocation)

    func transactionCount(in file: BackupFile) -> Int? {
        guard let data = try? Data(contentsOf: file.url) else { return nil }
        struct Partial: Decodable {
            struct EmptyTx: Decodable { init(from _: Decoder) throws {} }
            let transactions: [EmptyTx]
        }
        return (try? JSONDecoder().decode(Partial.self, from: data))?.transactions.count
    }

    // MARK: - Restore

    @MainActor
    @discardableResult
    func restore(
        from file: BackupFile,
        into context: ModelContext,
        replaceExisting: Bool = false,
        progress: @MainActor (BackupService.RestorePhase) -> Void
    ) async throws -> BackupImportResult {
        try await BackupService.restore(from: file.url, into: context, replaceExisting: replaceExisting, progress: progress)
    }

    // MARK: - Delete

    func deleteBackup(_ file: BackupFile) {
        let fm = FileManager.default
        if let url = file.agURL   { try? fm.removeItem(at: url) }
        if let url = file.docsURL { try? fm.removeItem(at: url) }
    }

    // MARK: - Private Helpers

    private func pruneOldBackups(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let backups = files.filter {
            $0.lastPathComponent.hasPrefix("anka-backup-") &&
            $0.pathExtension == "json"
        }
        .sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return d1 > d2
        }

        if backups.count > Self.maxBackups {
            backups.dropFirst(Self.maxBackups).forEach {
                try? fm.removeItem(at: $0)
            }
        }
    }

    private static func makeFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        return "anka-backup-\(fmt.string(from: Date())).json"
    }
}
