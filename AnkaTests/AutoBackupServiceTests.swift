import Testing
import Foundation
@testable import Anka

/// Covers the rolling-backup retention rule: only the newest `keep`
/// `anka-backup-*.json` files survive a prune; unrelated files are untouched.
struct AutoBackupServiceTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoBackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Creates a fake backup file with a controlled creation date.
    private func makeBackup(named name: String, in dir: URL, ageInMinutes: Int) throws {
        let url = dir.appendingPathComponent(name)
        try Data("{}".utf8).write(to: url)
        let date = Date().addingTimeInterval(TimeInterval(-ageInMinutes * 60))
        try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
    }

    @Test func pruneKeepsNewestSeven() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 10 backups, backup-0 newest … backup-9 oldest.
        for i in 0..<10 {
            try makeBackup(named: "anka-backup-\(i).json", in: dir, ageInMinutes: i)
        }

        AutoBackupService.prune(directory: dir, keep: 7)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(remaining.count == 7)
        // The three oldest are gone.
        #expect(!remaining.contains("anka-backup-7.json"))
        #expect(!remaining.contains("anka-backup-8.json"))
        #expect(!remaining.contains("anka-backup-9.json"))
        #expect(remaining.contains("anka-backup-0.json"))
    }

    @Test func pruneIgnoresUnrelatedFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0..<9 {
            try makeBackup(named: "anka-backup-\(i).json", in: dir, ageInMinutes: i)
        }
        // Not backups: wrong prefix / wrong extension — must survive even
        // though they'd be "oldest".
        try makeBackup(named: "notes.json", in: dir, ageInMinutes: 999)
        try makeBackup(named: "anka-backup-old.txt", in: dir, ageInMinutes: 999)

        AutoBackupService.prune(directory: dir, keep: 7)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(remaining.contains("notes.json"))
        #expect(remaining.contains("anka-backup-old.txt"))
        #expect(remaining.filter { $0.hasPrefix("anka-backup-") && $0.hasSuffix(".json") }.count == 7)
    }

    @Test func pruneNoOpUnderLimit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0..<3 {
            try makeBackup(named: "anka-backup-\(i).json", in: dir, ageInMinutes: i)
        }

        AutoBackupService.prune(directory: dir, keep: 7)

        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 3)
    }
}
