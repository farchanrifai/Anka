import SwiftUI

struct ExportSheet: View {
    let transactions: [Transaction]
    @Environment(\.dismiss) private var dismiss

    enum ExportPeriod: String, CaseIterable {
        case allTime   = "All Time"
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisYear  = "This Year"
        case custom    = "Custom Range"
    }

    @State private var period: ExportPeriod = .allTime
    @State private var customStart: Date = Date.now.addingMonths(-1)
    @State private var customEnd: Date = .now

    /// Cached result of `Self.filter(...)`. Recomputed only when the period or
    /// custom range changes (or the transaction set updates) — previously this
    /// was a computed property re-run several times per render.
    @State private var filtered: [Transaction] = []

    /// Temp CSV file backing the `ShareLink`. Regenerated whenever `filtered`
    /// changes; nil when there's nothing to export. Using `ShareLink` instead
    /// of a hand-presented `UIActivityViewController` fixes the iPad popover
    /// crash (no source anchor) — see AUDIT.md X1.
    @State private var exportURL: URL?

    // Cached formatters — DateFormatter is expensive to allocate.
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()
    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    Picker("Period", selection: $period) {
                        ForEach(ExportPeriod.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if period == .custom {
                    Section("Date Range") {
                        DatePicker("From", selection: $customStart,
                                   in: ...customEnd, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: customStart..., displayedComponents: .date)
                    }
                }

                Section {
                    let count = filtered.count
                    HStack {
                        Text(count == 0 ? "Nothing to export" : "\(count) transaction\(count == 1 ? "" : "s")")
                            .foregroundStyle(count == 0 ? .red : .secondary)
                        Spacer()
                        if count > 0 {
                            Text(filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }.idrFormatted)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let url = exportURL {
                        ShareLink(item: url, preview: SharePreview(filename())) {
                            Text("Export")
                        }
                        .disabled(filtered.isEmpty)
                        .tint(.primary)
                    } else {
                        Button("Export") {}
                            .disabled(true)
                            .tint(.primary)
                    }
                }
            }
        }
        .onAppear { recomputeFiltered() }
        .onChange(of: period) { recomputeFiltered() }
        .onChange(of: customStart) { recomputeFiltered() }
        .onChange(of: customEnd) { recomputeFiltered() }
        .onChange(of: transactions) { recomputeFiltered() }
    }

    // MARK: - Filtering

    private func recomputeFiltered() {
        filtered = Self.filter(transactions, period: period,
                               customStart: customStart, customEnd: customEnd)
        regenerateExportFile()
    }

    /// Writes the current `filtered` set to a temp CSV the `ShareLink` exports.
    /// Reuses a stable filename per period so we don't litter the temp dir.
    private func regenerateExportFile() {
        guard !filtered.isEmpty else { exportURL = nil; return }
        let csv = CSVService.export(filtered)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename())
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    /// Pure filter so it can run off the view-update path. Uses the safe date
    /// helpers (no force-unwrapped Calendar arithmetic).
    private static func filter(_ transactions: [Transaction], period: ExportPeriod,
                               customStart: Date, customEnd: Date) -> [Transaction] {
        let cal = Calendar.current
        let now = Date.now
        switch period {
        case .allTime:
            return transactions
        case .thisMonth:
            return transactions.filter { $0.date >= now.startOfMonth && $0.date <= now }
        case .lastMonth:
            // Half-open: [startOfMonth, startOfNextMonth) — no 1-second end gap (D8).
            let last = now.addingMonths(-1)
            return transactions.filter { $0.date >= last.startOfMonth && $0.date < last.startOfNextMonth }
        case .thisYear:
            let yearStart = now.startOfYear
            return transactions.filter { $0.date >= yearStart && $0.date <= now }
        case .custom:
            // Exclusive upper bound = start of the day after the end date.
            let endExclusive = cal.startOfDay(for: customEnd).addingDays(1)
            return transactions.filter { $0.date >= customStart && $0.date < endExclusive }
        }
    }

    // MARK: - Filename

    private func filename() -> String {
        switch period {
        case .allTime:   return "anka-all.csv"
        case .thisMonth: return "anka-\(Self.monthFormatter.string(from: .now)).csv"
        case .lastMonth: return "anka-\(Self.monthFormatter.string(from: Date.now.addingMonths(-1))).csv"
        case .thisYear:  return "anka-\(Self.yearFormatter.string(from: .now)).csv"
        case .custom:
            let start = Self.monthFormatter.string(from: customStart)
            let end = Self.monthFormatter.string(from: customEnd)
            return "anka-\(start)-to-\(end).csv"
        }
    }
}
