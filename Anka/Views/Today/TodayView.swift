import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @State private var viewModel = TodayViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            DSColor.bgPrimary
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    heroSection

                    if viewModel.groupedByDay.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(viewModel.groupedByDay, id: \.date) { group in
                            Section {
                                ForEach(group.transactions, id: \.id) { tx in
                                    transactionRow(tx)
                                        .padding(.horizontal, DSSpacing.lg)
                                        .padding(.vertical, DSSpacing.sm)
                                }
                            } header: {
                                dayHeader(for: group)
                            }
                        }
                    }

                    Spacer()
                        .frame(height: DSSpacing.xxxl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            viewModel.update(transactions: allTransactions)
        }
        .onChange(of: allTransactions) { _, newTransactions in
            viewModel.update(transactions: newTransactions)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: DSSpacing.sm) {
            Text("This Month")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DSSpacing.sm) {
                Text(String(format: "%.0f", viewModel.heroTotal))
                    .font(.dsHero)
                    .foregroundStyle(viewModel.heroTotal >= 0 ? DSColor.positive : DSColor.negative)

                Spacer()
            }

            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Income")
                        .font(.dsBadge)
                        .foregroundStyle(DSColor.textMuted)
                    Text(String(format: "%.2f", viewModel.totalIncome))
                        .font(.dsSubhead)
                        .foregroundStyle(DSColor.positive)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expense")
                        .font(.dsBadge)
                        .foregroundStyle(DSColor.textMuted)
                    Text(String(format: "%.2f", viewModel.totalExpense))
                        .font(.dsSubhead)
                        .foregroundStyle(DSColor.negative)
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColor.bgCard)
        .cornerRadius(DSRadius.large)
        .padding(DSSpacing.lg)
        .padding(.top, DSSpacing.lg)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(DSColor.textMuted)

            VStack(spacing: DSSpacing.sm) {
                Text("No Transactions Yet")
                    .font(.dsHeadline)
                    .foregroundStyle(DSColor.textPrimary)

                Text("Tap Add to log your first expense or income")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxxl)
    }

    // MARK: - Day Header

    private func dayHeader(for group: TransactionGroup) -> some View {
        let dailyTotal = viewModel.dailyTotal(for: group.transactions)
        let sign = dailyTotal >= 0 ? "+" : ""

        return HStack {
            Text(viewModel.shortDateLabel(for: group.date))
                .font(.dsBadge)
                .foregroundStyle(DSColor.textMuted)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.md)
                .background(DSColor.bgCard, in: Capsule())

            Spacer()

            if dailyTotal != 0 {
                Text("\(sign)\(String(format: "%.2f", dailyTotal))")
                    .font(.dsBadge)
                    .foregroundStyle(dailyTotal > 0 ? DSColor.positive : DSColor.negative)
                    .frame(height: 28)
                    .padding(.horizontal, DSSpacing.md)
                    .background(DSColor.bgCard, in: Capsule())
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.bgPrimary)
    }

    // MARK: - Transaction Row

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: DSSpacing.md) {
            // Category emoji
            ZStack {
                Circle()
                    .fill((tx.category.map { Color(hex: $0.colorHex) } ?? DSColor.accent).opacity(0.15))
                    .frame(width: 54, height: 54)

                Text(tx.category?.emoji ?? "💳")
                    .font(.system(size: 24))
            }

            // Details
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.category?.name ?? "Uncategorized")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textMuted)

                let desc = tx.note?.isEmpty == false ? tx.note! : (tx.category?.name ?? tx.type.displayName)
                Text(desc)
                    .font(.dsSubhead)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Amount
            let sign = tx.type == .expense ? "" : "+ "
            Text("\(sign)\(String(format: "%.2f", tx.amount))")
                .font(.dsBadge)
                .foregroundStyle(tx.type == .expense ? DSColor.negative : DSColor.positive)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, 6)
                .background(DSColor.bgCard, in: Capsule())
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Phase 5+: implement delete
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        TodayView()
    }
    .modelContainer(SampleData.container())
}
