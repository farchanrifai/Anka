import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Backup & Restore Settings

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance

    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder)                private var allCategories: [Category]

    @State private var backups: [AutoBackupService.BackupFile] = []
    @State private var txCounts: [String: Int] = [:]
    @State private var isBackingUp  = false
    @State private var isRestoring  = false
    @State private var confirmRestore: AutoBackupService.BackupFile? = nil
    @State private var restoreResult: BackupImportResult? = nil
    @State private var showResultAlert = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    @State private var showFileImporter = false
    @State private var confirmRestoreURL: URL? = nil
    @State private var restorePhase: BackupService.RestorePhase? = nil
    @State private var backupProgress: String? = nil

    private let service = AutoBackupService.shared

    var body: some View {
        List {
            // MARK: Status Section
            Section {
                HStack {
                    Label("Status", systemImage: "externaldrive.badge.checkmark")
                    Spacer()
                    Text("On")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Last Backup", systemImage: "clock")
                    Spacer()
                    Text(lastBackupText)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await backupNow() }
                } label: {
                    HStack(spacing: 8) {
                        if isBackingUp {
                            ProgressView().controlSize(.small)
                        }
                        Text(isBackingUp ? "Backing up…" : "Back Up Now")
                    }
                }
                .disabled(isBackingUp)
            } header: {
                Text("Auto-Backup")
            } footer: {
                Text("Anka backs up automatically when you open the app (at most once a day) and shortly after you add, edit, or delete transactions. You can also back up manually any time.")
            }
            .listRowBackground(appearance.bgCard(scheme))

            // MARK: Files Section
            Section {
                if backups.isEmpty {
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(backups) { file in
                        BackupFileRow(
                            file: file,
                            txCount: txCounts[file.id]
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                confirmRestore = file
                            } label: {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteBackup(file)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Backup Files")
            } footer: {
                Text("Backups are saved locally on this device in two locations. They are not synced to iCloud. Up to 7 backups are kept automatically.")
            }
            .listRowBackground(appearance.bgCard(scheme))

            // MARK: Restore from File Section
            Section {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Restore from File…", systemImage: "folder")
                }
            } footer: {
                Text("Pick an Anka backup JSON file from the Files app or iCloud Drive.")
            }
            .listRowBackground(appearance.bgCard(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadBackups()
            await loadTxCounts()
        }
        .overlay {
            if isRestoring {
                RestoreProgressOverlay(phase: restorePhase)
            } else if isBackingUp, let label = backupProgress {
                RestoreProgressOverlay(phase: nil, indeterminateLabel: label)
            }
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let file = confirmRestore {
                Button("Merge with current data", role: .none) {
                    Task { await restoreBackup(file, replaceExisting: false) }
                    confirmRestore = nil
                }
                Button("Replace all current data", role: .destructive) {
                    Task { await restoreBackup(file, replaceExisting: true) }
                    confirmRestore = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmRestore = nil }
        } message: {
            Text("Merging skips duplicates safely. Replacing will delete local transactions not in the backup.")
        }
        .alert("Restore Complete", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let r = restoreResult {
                Text("Imported: \(r.imported)\nUpdated: \(r.updated)\nDeleted: \(r.deleted)\nSkipped: \(r.skipped)")
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    confirmRestoreURL = url
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
        .confirmationDialog(
            "Restore this file?",
            isPresented: Binding(
                get: { confirmRestoreURL != nil },
                set: { if !$0 { confirmRestoreURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let url = confirmRestoreURL {
                Button("Merge with current data", role: .none) {
                    Task { await restoreFromURL(url, replaceExisting: false) }
                    confirmRestoreURL = nil
                }
                Button("Replace all current data", role: .destructive) {
                    Task { await restoreFromURL(url, replaceExisting: true) }
                    confirmRestoreURL = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmRestoreURL = nil }
        } message: {
            Text("Merging skips duplicates safely. Replacing will delete local transactions not in the backup.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onAppear { loadBackups() }
        .task { await loadTxCounts() }
    }

    // MARK: - Last Backup Text

    private var lastBackupText: String {
        let ts = UserDefaults.standard.double(forKey: AutoBackupService.lastBackupKey)
        guard ts > 0 else { return "Never" }
        return RelativeDateTimeFormatter()
            .localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }

    // MARK: - Actions

    private func loadBackups() {
        backups = service.listBackups()
        txCounts = [:]
    }

    private func loadTxCounts() async {
        for file in backups {
            if let count = service.transactionCount(in: file) {
                txCounts[file.id] = count
            }
        }
    }

    private func backupNow() async {
        isBackingUp = true
        backupProgress = "Backing up…"
        await service.performBackup(
            transactions: Array(allTransactions),
            categories: Array(allCategories)
        )
        loadBackups()
        await loadTxCounts()
        isBackingUp = false
        backupProgress = nil
    }

    private func restoreBackup(_ file: AutoBackupService.BackupFile, replaceExisting: Bool) async {
        isRestoring = true
        restorePhase = .reading
        do {
            let result = try await service.restore(
                from: file, into: modelContext, replaceExisting: replaceExisting
            ) { phase in
                restorePhase = phase
            }
            restoreResult = result
            showResultAlert = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
        isRestoring = false
        restorePhase = nil
    }

    private func restoreFromURL(_ url: URL, replaceExisting: Bool) async {
        isRestoring = true
        restorePhase = .reading
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await BackupService.restore(
                from: url, into: modelContext, replaceExisting: replaceExisting
            ) { phase in
                restorePhase = phase
            }
            restoreResult = result
            showResultAlert = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
        isRestoring = false
        restorePhase = nil
    }

    private func deleteBackup(_ file: AutoBackupService.BackupFile) {
        service.deleteBackup(file)
        withAnimation { backups.removeAll { $0.id == file.id } }
        txCounts.removeValue(forKey: file.id)
    }
}

// MARK: - Backup File Row

private struct BackupFileRow: View {
    let file: AutoBackupService.BackupFile
    let txCount: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayDate)
                    .font(.system(size: 15, weight: .medium))

                HStack(spacing: 6) {
                    if let count = txCount {
                        Text("\(count) transaction\(count == 1 ? "" : "s")")
                    } else {
                        Text("counting…")
                            .redacted(reason: .placeholder)
                    }
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(formattedSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(relativeDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            ShareLink(item: file.url, preview: SharePreview(file.name)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var displayDate: String {
        file.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
    }

    private var relativeDate: String {
        RelativeDateTimeFormatter()
            .localizedString(for: file.createdAt, relativeTo: Date())
    }
}

// MARK: - Restore Progress Overlay

private struct RestoreProgressOverlay: View {
    let phase: BackupService.RestorePhase?
    var indeterminateLabel: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                switch phase {
                case .processing(let done, let total) where total > 0:
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text("Restoring \(done) of \(total)…")
                        .font(.subheadline)
                        .monospacedDigit()
                default:
                    ProgressView().controlSize(.large)
                    Text(label)
                        .font(.headline)
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.large))
        }
    }

    private var label: String {
        if let indeterminateLabel { return indeterminateLabel }
        switch phase {
        case .reading:    return "Reading file…"
        case .saving:     return "Saving…"
        case .processing: return "Restoring…"
        case .none:       return "Working…"
        }
    }
}
