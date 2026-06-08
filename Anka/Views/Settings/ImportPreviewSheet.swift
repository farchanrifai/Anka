import SwiftUI

struct ImportPreviewSheet: View {
    let preview: CSVService.PreviewResult
    let onConfirm: ([CSVService.ParsedTransaction], [(row: Int, message: String)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance

    private var grouped: [(label: String, date: Date, total: Double, items: [CSVService.ParsedTransaction])] {
        let cal = Calendar.current
        var byDay: [Date: [CSVService.ParsedTransaction]] = [:]
        var totals: [Date: Double] = [:]
        for tx in preview.transactions {
            let day = cal.startOfDay(for: tx.date)
            byDay[day, default: []].append(tx)
            totals[day, default: 0] += tx.amount
        }
        return byDay.keys
            .sorted(by: >)
            .map { day in (
                label: day.sectionLabel,
                date: day,
                total: totals[day] ?? 0,
                items: (byDay[day] ?? []).sorted { $0.date > $1.date }
            )}
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section {
                    let count = preview.transactions.count
                    let total = preview.transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                    HStack {
                        Text("\(count) transaction\(count == 1 ? "" : "s") ready to import")
                        Spacer()
                        Text(total.idrFormatted)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(appearance.bgGrouped(scheme))
                .listSectionSeparator(.hidden)

                // Parse warnings
                if !preview.parseErrors.isEmpty {
                    Section("\(preview.parseErrors.count) row\(preview.parseErrors.count == 1 ? "" : "s") skipped") {
                        ForEach(preview.parseErrors, id: \.row) { err in
                            Text("Row \(err.row): \(err.message)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Transaction list grouped by day
                ForEach(grouped, id: \.label) { group in
                    Section(header: sectionHeader(group)) {
                        ForEach(group.items) { tx in
                            transactionRow(tx)
                                .listRowBackground(appearance.bgCard(scheme))
                                .listRowSeparatorTint(.primary.opacity(0.07))
                                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(appearance.bgGrouped(scheme))
            .navigationTitle("Preview import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(preview.transactions.count)") {
                        onConfirm(preview.transactions, preview.parseErrors)
                        dismiss()
                    }
                    .disabled(preview.transactions.isEmpty)
                    .tint(.primary)
                }
            }
        }
    }

    private func sectionHeader(_ group: (label: String, date: Date, total: Double, items: [CSVService.ParsedTransaction])) -> some View {
        HStack {
            Text(group.label)
            Spacer()
            Text(group.total.idrFormatted)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.horizontal, -4)
    }

    private func transactionRow(_ tx: CSVService.ParsedTransaction) -> some View {
        HStack(spacing: 10) {
            if let cat = tx.matchedCategory {
                Text(cat.emoji)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }
            Text(tx.note ?? tx.categoryName ?? "Uncategorized")
                .font(.system(size: 14))
            Spacer()
            Text(tx.amount.idrFormatted)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
