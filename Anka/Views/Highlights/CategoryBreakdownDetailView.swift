import SwiftUI
import SwiftData

struct CategoryBreakdownDetailView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    private var monthStart: Date { Date().startOfMonth }
    private var monthEnd:   Date { monthStart.startOfNextMonth }

    private struct CategoryGroup: Identifiable {
        let id: UUID
        let emoji: String
        let name: String
        let colorHex: String
        let transactions: [Transaction]
        let total: Double
    }

    private var grouped: [CategoryGroup] {
        let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let month = allTransactions.filter {
            $0.type == .expense && $0.date >= monthStart && $0.date < monthEnd
        }
        var buckets: [UUID: [Transaction]] = [:]
        for tx in month { buckets[tx.category?.id ?? uncategorizedID, default: []].append(tx) }
        return buckets.map { key, txs in
            let cat   = txs.first?.category
            let total = txs.reduce(0) { $0 + $1.convertedAmount(to: AppCurrency.code) }
            return CategoryGroup(
                id: key,
                emoji: cat?.emoji ?? "📁",
                name: cat?.name ?? "Uncategorized",
                colorHex: cat?.colorHex ?? "999999",
                transactions: txs.sorted { $0.date > $1.date },
                total: total
            )
        }.sorted { $0.total > $1.total }
    }

    private var chartData: [CategorySpendHighlight] {
        grouped.map { g in
            CategorySpendHighlight(id: g.id, emoji: g.emoji, name: g.name, colorHex: g.colorHex, amount: g.total)
        }
    }

    var body: some View {
        List {
            // Full bar chart card — same design as TopCategoryCard / MonthlyHighlightCard
            Section {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Text("📊 Categories")
                        .font(.dsFootnoteSemi)
                        .foregroundStyle(DSColor.accent)

                    Text("All expenses in \(monthStart.monthName) by category.")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textPrimary)

                    Divider().background(Color.gray.opacity(0.3))

                    CategoryBarRows(categories: chartData)
                }
                .padding(DSSpacing.md)
                .background(DSColor.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Transaction list per category
            ForEach(grouped) { group in
                Section {
                    ForEach(group.transactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.note ?? group.name)
                                    .font(.dsFootnoteMedium)
                                    .foregroundStyle(DSColor.textPrimary)
                                    .lineLimit(1)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.dsCaption2)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            Text(tx.convertedAmount(to: AppCurrency.code).rupiah)
                                .font(.dsFootnoteSemi)
                                .foregroundStyle(DSColor.textPrimary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 8, height: 8)
                        Text(group.emoji + " " + group.name)
                            .font(.dsFootnoteSemi)
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer()
                        Text(group.total.rupiah)
                            .font(.dsCaption2Semi)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories · \(monthStart.monthName)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
