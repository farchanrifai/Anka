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
    /// Shared delay before both the donut and weekly trend charts fade in
    /// together (see `chartSection`'s `.task`).
    private let chartReadyDelay: TimeInterval = 0.38

    private static let chartHeight: CGFloat = 336  // matches Spendy MainView

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodHeader
                chartSection
                weeklyTrendSection
            }
            // Extra top padding clears the sheet's grab handle so it doesn't
            // crowd the period label.
            .padding(.top, DSSpacing.lg)
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
            try? await Task.sleep(nanoseconds: UInt64(chartReadyDelay * 1_000_000_000))
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

    // MARK: - Period Header

    private var periodHeader: some View {
        VStack(spacing: 4) {
            Text(vm.monthLabel)
                .font(.dsTitle3)
                .foregroundStyle(DSColor.textPrimary)
            Text(vm.periodType)
                .font(.dsCaption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weekly Trend

    // Shares `chartReady` with `chartSection` so both charts fade in together
    // once the push/sheet transition has settled.
    @ViewBuilder
    private var weeklyTrendSection: some View {
        if chartReady {
            WeeklyTrendChartView(weeklyData: vm.weeklySpend)
                .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Weekly trend")
                    .font(.dsHeadline)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.screenEdge)

                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .fill(DSColor.bgSecondary)
                    .frame(height: 180)
                    .padding(.horizontal, DSSpacing.screenEdge)
            }
        }
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
