import SwiftUI

struct ImportSummarySheet: View {
    let result: CSVService.ImportResult?
    let error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let err = error, result == nil {
                    Section {
                        Label(err, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else if let r = result {
                    Section("Summary") {
                        Label("\(r.imported) imported", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if r.skipped > 0 {
                            Label("\(r.skipped) skipped", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    if !r.errors.isEmpty {
                        Section("Skipped rows") {
                            ForEach(r.errors, id: \.self) { msg in
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Expected format") {
                    Text("date, type, category, amount, note, tags, currency, paymentMethod")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("date: 2024-03-15 or ISO 8601")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("type: expense or income (default: expense)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("category, note, tags, currency, paymentMethod: optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.primary)
                }
            }
        }
    }
}
