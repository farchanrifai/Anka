import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var vm = StatsViewModel()

    private static let chartHeight: CGFloat = 336  // matches Spendy MainView

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                chartSection
                topCategoriesSection
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(DSColor.bgPrimary.ignoresSafeArea())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { feedVM() }
        .onChange(of: allTransactions) { feedVM() }
        .onChange(of: allCategories)   { feedVM() }
        .task(id: vm.refreshKey) { await vm.refresh() }
    }

    private func feedVM() {
        vm.update(transactions: allTransactions, categories: allCategories)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        ZStack {
            DonutChartView(
                categoryData: vm.categorySpend,
                totalSpent:   vm.monthTotal,
                budget:       0, // budgets not implemented yet; "Set Budget >" shown but inert
                monthName:    vm.shortMonthLabel,
                onSetBudget:  {},
                onSwipe:      { vm.navigateMonth(by: $0) }
            )
            .id(vm.refreshKey)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
        }
        .frame(height: Self.chartHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.refreshKey)
        .padding(.horizontal, DSSpacing.screenEdge)
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.categorySpend.isEmpty {
                Text("Top Categories")
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, DSSpacing.screenEdge)

                categoriesList
            } else {
                emptyState
            }
        }
    }

    private var categoriesList: some View {
        let items = Array(vm.categorySpend.prefix(5))
        return VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                categoryRow(item)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(DSColor.bgSecondary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, DSSpacing.screenEdge)
    }

    private func categoryRow(_ item: CategorySpendData) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.dsBodySemi)
                    .foregroundStyle(.primary)
                let pct = vm.monthTotal > 0 ? item.amount / vm.monthTotal * 100 : 0
                Text(String(format: "%.0f%% of total", pct))
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Rp \(item.amount.idrShort)")
                .font(.dsFootnoteMedium)
                .foregroundStyle(.primary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No expenses for \(vm.monthLabel)")
                .font(.dsBodyMedium)
            Text("Swipe the donut left or right to navigate months.")
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .modelContainer(SampleData.container())
}
