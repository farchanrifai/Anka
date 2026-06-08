import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance
    @Query(sort: \Transaction.date) private var transactions: [Transaction]
    @Query private var categories: [Category]

    // Transaction export
    @State private var showTransactionExport = false

    // Transaction import
    @State private var isImportingTransactions = false
    @State private var pendingTransactionPreview: CSVService.PreviewResult?
    @State private var showTransactionPreview = false
    @State private var transactionImportResult: CSVService.ImportResult?
    @State private var transactionImportError: String?
    @State private var showTransactionSummary = false

    // File importer
    @State private var showFileImporter = false

    var body: some View {
        List {
            Section("Transactions") {
                Button {
                    showTransactionExport = true
                } label: {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                .tint(.primary)

                Button {
                    showFileImporter = true
                } label: {
                    if isImportingTransactions {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading file…")
                        }
                    } else {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                }
                .tint(.primary)
                .disabled(isImportingTransactions)
            }
            .listRowBackground(appearance.bgCard(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Import & Export")
        .navigationBarTitleDisplayMode(.inline)
        // Transaction sheets
        .sheet(isPresented: $showTransactionExport) {
            ExportSheet(transactions: transactions)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleTransactionFilePick(result)
        }
        .sheet(isPresented: $showTransactionPreview) {
            if let preview = pendingTransactionPreview {
                ImportPreviewSheet(preview: preview) { parsed, errors in
                    commitTransactionImport(parsed: parsed, skippedErrors: errors)
                }
            }
        }
        .sheet(isPresented: $showTransactionSummary) {
            ImportSummarySheet(result: transactionImportResult, error: transactionImportError)
        }
    }

    // MARK: - Transaction import

    private func handleTransactionFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            transactionImportError = err.localizedDescription
            transactionImportResult = nil
            showTransactionSummary = true
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportingTransactions = true
            Task { @MainActor in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let preview = try CSVService.parsePreview(
                        from: url,
                        availableCategories: categories
                    )
                    pendingTransactionPreview = preview
                    showTransactionPreview = true
                } catch {
                    transactionImportError = error.localizedDescription
                    transactionImportResult = nil
                    showTransactionSummary = true
                }
                isImportingTransactions = false
            }
        }
    }

    private func commitTransactionImport(
        parsed: [CSVService.ParsedTransaction],
        skippedErrors: [(row: Int, message: String)]
    ) {
        do {
            let result = try CSVService.commit(
                parsed,
                skippedErrors: skippedErrors,
                into: modelContext
            )
            transactionImportResult = result
            transactionImportError = nil
        } catch {
            transactionImportResult = nil
            transactionImportError = error.localizedDescription
        }
        showTransactionSummary = true
    }
}
