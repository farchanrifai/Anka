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
        let id: UUID
        let name: String       // anka-backup-2026-05-22T14-30-00.json
        let url: URL           // preferred URL: App Group > Documents
        let agURL: URL?        // App Group copy (nil if absent)
        let docsURL: URL?      // Documents copy (nil if absent)
        let createdAt: Date
        let fileSize: Int64

        init(name: String, url: URL, agURL: URL?, docsURL: URL?,
             createdAt: Date, fileSize: Int64) {
            self.id        = UUID()
            self.name      = name
            self.url       = url
            self.agURL     = agURL
            self.docsURL   = docsURL
            self.createdAt = createdAt
            self.fileSize  = fileSize
        }
    }

    // MARK: - Private Payload

    private struct AnkaAutoBackup: Codable {
        static let currentVersion = 1
        let version: Int
        let exportedAt: Date
        let transactions: [BackupTransaction]

        struct BackupTransaction: Codable {
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

    // MARK: - Constants

    private static let maxBackups     = 7
    private static let lastBackupKey  = "autoBackupLastDate"
    private static let backupInterval: TimeInterval = 24 * 3600

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting     = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Perform Backup

    func performBackup(
        transactions: [Transaction],
        categories: [Category]
    ) async {
        // 1. Snapshot model data on MainActor (safe — @Model objects live here)
        let txSnapshots = transactions.filter { !$0.isDeleted }.map { tx in
            AnkaAutoBackup.BackupTransaction(
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
        let payload = AnkaAutoBackup(
            version: AnkaAutoBackup.currentVersion,
            exportedAt: Date(),
            transactions: txSnapshots
        )
        guard let data = try? Self.encoder.encode(payload) else { return }

        // 2. Resolve target directories (URL and Data are Sendable value types)
        let fm       = FileManager.default
        let agDir    = fm.containerURL(forSecurityApplicationGroupIdentifier: PlatformPaths.appGroupID)?
                          .appendingPathComponent("Backups")
        let docsDir  = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
                          .appendingPathComponent("Backups")
        let filename = Self.makeFilename()
        let agFile   = agDir?.appendingPathComponent(filename)
        let docsFile = docsDir?.appendingPathComponent(filename)

        // 3. Write concurrently in detached background tasks
        async let writeAG: Void = Task.detached(priority: .background) {
            guard let dir = agDir, let file = agFile else { return }
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }.value

        async let writeDocs: Void = Task.detached(priority: .background) {
            guard let dir = docsDir, let file = docsFile else { return }
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }.value

        _ = await writeAG
        _ = await writeDocs

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

    @discardableResult
    func restore(from file: BackupFile, into context: ModelContext, replaceExisting: Bool = false) throws -> BackupImportResult {
        try BackupService.restore(from: file.url, into: context, replaceExisting: replaceExisting)
    }

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
