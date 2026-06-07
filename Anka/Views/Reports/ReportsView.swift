import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @State private var viewModel = ReportsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            DSColor.bgPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    monthSelector
                    summaryCards

                    if !viewModel.categoryChartData.isEmpty {
                        donutSection
                    }

                    if !viewModel.dailyChartData.isEmpty {
                        barSection
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

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack(spacing: DSSpacing.md) {
            Button(action: viewModel.previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSColor.accent)
            }

            Text(viewModel.monthYearLabel())
                .font(.dsHeadline)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity)

            Button(action: viewModel.nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSColor.accent)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColor.bgCard)
        .cornerRadius(DSRadius.large)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.lg)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Total Spent")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textMuted)
                Text(String(format: "%.2f", viewModel.totalExpense))
                    .font(.dsHeadline)
                    .foregroundStyle(DSColor.negative)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.md)
            .background(DSColor.bgCard)
            .cornerRadius(DSRadius.medium)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Daily Avg")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textMuted)
                Text(String(format: "%.2f", viewModel.averagePerDay))
                    .font(.dsHeadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.md)
            .background(DSColor.bgCard)
            .cornerRadius(DSRadius.medium)
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    // MARK: - Donut Chart

    private var donutSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("By Category")
                .font(.dsSubhead)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.lg)

            Chart(viewModel.categoryChartData, id: \.category.id) { data in
                SectorMark(
                    angle: .value("Amount", data.amount),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Category", data.category.name))
                .opacity(0.8)
            }
            .frame(height: 250)
            .padding(.horizontal, DSSpacing.lg)

            // Legend
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(viewModel.categoryChartData.prefix(6), id: \.category.id) { data in
                    HStack(spacing: DSSpacing.md) {
                        Text(data.category.emoji)
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.category.name)
                                .font(.dsCaption)
                                .foregroundStyle(DSColor.textPrimary)
                            Text(String(format: "%.1f%%", data.percentage))
                                .font(.dsBadge)
                                .foregroundStyle(DSColor.textMuted)
                        }

                        Spacer()

                        Text(String(format: "%.2f", data.amount))
                            .font(.dsBadge)
                            .foregroundStyle(DSColor.negative)
                    }
                    .padding(DSSpacing.md)
                    .background(DSColor.bgCard)
                    .cornerRadius(DSRadius.medium)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    // MARK: - Bar Chart (Daily Trend)

    private var barSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Daily Spending")
                .font(.dsSubhead)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.lg)

            Chart(viewModel.dailyChartData, id: \.date) { data in
                BarMark(
                    x: .value("Day", Calendar.current.component(.day, from: data.date)),
                    y: .value("Amount", data.amount)
                )
                .foregroundStyle(DSColor.accent)
                .opacity(0.8)
            }
            .chartYAxis(.hidden)
            .frame(height: 180)
            .padding(.horizontal, DSSpacing.lg)
        }
    }
}

#Preview {
    NavigationStack {
        ReportsView()
    }
    .modelContainer(SampleData.container())
}
