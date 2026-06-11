import SwiftUI
import SwiftData

struct StatsView: View {
    // Data is passed in from TodayView (which already queried it) rather than
    // re-fetched here. A self-owned `@Query` fired a second full fetch on the
    // main thread *during the push transition*; on-device that blocked the
    // toolbar morph (empty-capsule freeze). Taking the already-materialized
    // arrays makes the first frame allocation-free so the push never stalls.
    let transactions: [Transaction]
    let categories: [Category]

    @State private var vm = StatsViewModel()

    /// Swift Charts construction is expensive (~hundreds of ms in Debug) and
    /// SwiftUI must render the destination's first frame *before* the push
    /// animation can start — building the donut up front stalled the
    /// transition, leaving the Today toolbar frozen mid-morph (empty glass
    /// capsule). First frame shows a cheap ring placeholder instead; the real
    /// chart fades in once the push has landed.
    @State private var chartReady = false

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
        .sensoryFeedback(.impact(weight: .light), trigger: vm.currentMonth)
        .onAppear { feedVM() }
        .onChange(of: transactions) { feedVM() }
        .onChange(of: categories)   { feedVM() }
        .task(id: vm.refreshKey) { await vm.refresh() }
    }

    private func feedVM() {
        vm.update(transactions: transactions, categories: categories)
    }

    // MARK: - Chart Section

    // No `.id(vm.refreshKey)` here — that forced a full Swift Charts teardown
    // + rebuild on every data version bump, including 2–3 times during the
    // push transition itself (the slow/janky open). DonutChartView already
    // crossfades its slices internally when the data signature changes;
    // month swipes and data updates animate without recreating the chart.
    private var chartSection: some View {
        ZStack {
            if chartReady {
                DonutChartView(
                    categoryData: vm.categorySpend,
                    totalSpent:   vm.monthTotal,
                    budget:       0, // budgets not implemented yet; "Set Budget >" shown but inert
                    monthName:    vm.shortMonthLabel,
                    onSetBudget:  {},
                    onSwipe:      { vm.navigateMonth(by: $0) }
                )
                .transition(.opacity)
            } else {
                chartPlaceholder
            }
        }
        .frame(height: Self.chartHeight)
        .padding(.horizontal, DSSpacing.screenEdge)
        .task {
            guard !chartReady else { return }
            // Let the push animation finish before paying the Charts build cost.
            try? await Task.sleep(nanoseconds: 380_000_000)
            withAnimation(.easeOut(duration: 0.2)) { chartReady = true }
        }
    }

    /// Visually matches DonutChartView's empty/placeholder state (gray ring,
    /// inner radius ratio 0.78) at near-zero render cost.
    private var chartPlaceholder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ringWidth = side / 2 * (1 - 0.78)
            Circle()
                .stroke(Color(.systemGray5), lineWidth: ringWidth)
                .frame(width: side - ringWidth, height: side - ringWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

/// Preview wrapper: owns the `@Query` (like TodayView does in the real app)
/// and feeds the results into StatsView.
private struct StatsPreviewHost: View {
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var body: some View {
        NavigationStack {
            StatsView(transactions: transactions, categories: categories)
        }
    }
}

#Preview {
    StatsPreviewHost()
        .modelContainer(SampleData.container())
}
