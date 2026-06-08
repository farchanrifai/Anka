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
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var customEnd: Date = .now

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
                    Button("Export") {
                        shareFiltered()
                        dismiss()
                    }
                    .disabled(filtered.isEmpty)
                    .tint(.primary)
                }
            }
        }
    }

    // MARK: - Filtering

    private var filtered: [Transaction] {
        let cal = Calendar.current
        let now = Date.now
        switch period {
        case .allTime:
            return transactions
        case .thisMonth:
            return transactions.filter { $0.date >= now.startOfMonth && $0.date <= now }
        case .lastMonth:
            let last = cal.date(byAdding: .month, value: -1, to: now)!
            return transactions.filter { $0.date >= last.startOfMonth && $0.date <= last.endOfMonth }
        case .thisYear:
            let yearStart = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
            return transactions.filter { $0.date >= yearStart && $0.date <= now }
        case .custom:
            let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd) ?? customEnd
            return transactions.filter { $0.date >= customStart && $0.date <= end }
        }
    }

    // MARK: - Share

    private func shareFiltered() {
        let csv = CSVService.export(filtered)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename())
        guard (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }

        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        presenter.present(av, animated: true)
    }

    private func filename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        switch period {
        case .allTime:   return "anka-all.csv"
        case .thisMonth: return "anka-\(f.string(from: .now)).csv"
        case .lastMonth:
            let last = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
            return "anka-\(f.string(from: last)).csv"
        case .thisYear:
            f.dateFormat = "yyyy"
            return "anka-\(f.string(from: .now)).csv"
        case .custom:
            let start = f.string(from: customStart)
            let end = f.string(from: customEnd)
            return "anka-\(start)-to-\(end).csv"
        }
    }
}
