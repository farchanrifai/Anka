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
    /// Month Stats opens on, inherited one-way from Today's selected month
    /// (falls back to the current month when Today is on a multi-month period).
    let initialMonth: Date

    @State private var vm = StatsViewModel()

    /// Applies `initialMonth` to the VM exactly once, on first appearance.
    @State private var didApplyInitialMonth = false

    /// Shared category selection — written by both the donut (tap a slice) and
    /// the breakdown list (tap a row), so the two stay in sync.
    @State private var selectedCategoryID: String?

    /// Swift Charts construction is expensive (~hundreds of ms in Debug) and
    /// SwiftUI must render the destination's first frame *before* the push
    /// animation can start — building the donut up front stalled the
    /// transition, leaving the Today toolbar frozen mid-morph (empty glass
    /// capsule). First frame shows a cheap ring placeholder instead; the real
    /// chart fades in once the push has landed.
    @State private var chartReady = false
    // Tightened from Spendy's 336 — the sheet reads more compact, in line with
    // the app's overall scale.
    private static let chartHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.xl) {
                monthStepper
                summaryHero
                statsContent
                weeklyTrendSection
            }
            // Extra top padding clears the sheet's grab handle so it doesn't
            // crowd the period label.
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xl)
        }
        .background(DSColor.bgPrimary.ignoresSafeArea())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: vm.currentMonth)
        .onAppear {
            if !didApplyInitialMonth {
                vm.currentMonth = initialMonth.startOfMonth
                didApplyInitialMonth = true
            }
            feedVM()
        }
        .onChange(of: transactions) { feedVM() }
        .onChange(of: categories)   { feedVM() }
        .onChange(of: vm.currentMonth) { selectedCategoryID = nil }
        .onChange(of: vm.isLoading) { _, isLoading in
            // Reveal the heavy chart the moment the first real refresh settles,
            // instead of after a hand-tuned sleep. This keeps the cheap
            // placeholder on first frame without baking in a fixed delay that
            // may feel early on fast devices or late on slow ones.
            guard !isLoading, !chartReady, didApplyInitialMonth else { return }
            withAnimation(.dsEaseSlow) { chartReady = true }
        }
        .task(id: vm.refreshKey) { await vm.refresh() }
    }

    private func feedVM() {
        vm.update(transactions: transactions, categories: categories)
    }

    // MARK: - Month stepper

    private var monthStepper: some View {
        HStack(spacing: DSSpacing.lg) {
            stepperButton(systemName: "chevron.left", delta: -1, disabled: false)

            // Tap the month label to jump back to the live month (the unused
            // `resetToCurrentMonth()` the audit flagged in U5). Disabled — and
            // styled as plain text — once already on the current month.
            Button {
                vm.resetToCurrentMonth()
            } label: {
                VStack(spacing: 2) {
                    Text(vm.monthLabel)
                        .font(.dsHeadlineSemi)
                        .foregroundStyle(DSColor.textPrimary)
                        .contentTransition(.numericText())
                    Text(vm.isOnCurrentMonth ? vm.periodType : "Tap to return to this month")
                        .font(.dsCaption2)
                        .foregroundStyle(vm.isOnCurrentMonth ? DSColor.textSecondary : DSColor.accentText)
                }
                .frame(minWidth: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(vm.isOnCurrentMonth)
            .accessibilityLabel("\(vm.monthLabel). \(vm.isOnCurrentMonth ? "" : "Tap to return to the current month.")")

            stepperButton(systemName: "chevron.right", delta: 1, disabled: vm.isOnCurrentMonth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSSpacing.screenEdge)
    }

    private func stepperButton(systemName: String, delta: Int, disabled: Bool) -> some View {
        Button {
            vm.navigateMonth(by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.dsHeadlineSemi)
                .foregroundStyle(disabled ? DSColor.textMuted : DSColor.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(delta < 0 ? "Previous month" : "Next month")
    }

    // MARK: - Summary hero

    private var summaryHero: some View {
        VStack(spacing: DSSpacing.md) {
            Text(rp(vm.monthTotal))
                .font(.dsTitle2Bold)
                .foregroundStyle(DSColor.textPrimary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            HStack(spacing: DSSpacing.md) {
                if let delta = vm.expenseDeltaPercent {
                    deltaPill(delta)
                }
                Text("\(vm.dailyAverage.idrShort)/day")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
            }

            HStack(spacing: DSSpacing.md) {
                summaryChip(label: "Income", value: rp(vm.incomeTotal), color: DSColor.positive)
                summaryChip(label: "Net", value: signedAmount(vm.netTotal),
                            color: vm.netTotal >= 0 ? DSColor.positive : DSColor.negative)
            }
            .padding(.top, DSSpacing.xs)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
    }

    private func deltaPill(_ delta: Double) -> some View {
        // Spending *less* than last month is good → green/down.
        let isDown = delta <= 0
        let color: Color = isDown ? DSColor.positive : DSColor.negative
        return HStack(spacing: 3) {
            Image(systemName: isDown ? "arrow.down" : "arrow.up")
                .font(.dsCaption2Bold)
            Text("\(abs(Int(delta.rounded())))% vs \(vm.previousMonthShortLabel)")
                .font(.dsCaptionSemi)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(DSOpacity.subtle), in: Capsule())
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.dsCaption2)
                .foregroundStyle(DSColor.textSecondary)
            Text(value)
                .font(.dsSubheadSemi)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.bgSecondary, in: RoundedRectangle(cornerRadius: DSRadius.medium))
    }

    /// "Rp 1,234,567" — matches the app's amount convention (never "IDR …").
    private func rp(_ value: Double) -> String { value.rupiah }

    /// "+Rp 1,200,000" / "-Rp 300,000" — signed, for the Net chip.
    private func signedAmount(_ value: Double) -> String { value.signedRupiah }

    // MARK: - Chart + breakdown content

    // `chartSection`'s donut is never torn down via `.id(refreshKey)` — that
    // forced a full Swift Charts rebuild on every data bump (the slow/janky
    // open). DonutChartView crossfades its slices internally instead.
    @ViewBuilder
    private var statsContent: some View {
        if !chartReady {
            chartPlaceholder
                .frame(height: Self.chartHeight)
                .padding(.horizontal, DSSpacing.screenEdge)
        } else if vm.categorySpend.isEmpty {
            emptyState
        } else {
            DonutChartView(
                categoryData: vm.categorySpend,
                totalSpent:   vm.monthTotal,
                budget:       0, // budgets not implemented yet
                monthName:    vm.shortMonthLabel,
                onSetBudget:  {},
                onSwipe:      { vm.navigateMonth(by: $0) },
                selectedID:   $selectedCategoryID
            )
            .frame(height: Self.chartHeight)
            .padding(.horizontal, DSSpacing.screenEdge)
            .transition(.opacity)

            categoryBreakdown
        }
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Spending by category")
                .font(.dsSubheadSemi)
                .foregroundStyle(DSColor.textSecondary)

            ForEach(vm.categorySpend) { data in
                Button {
                    withAnimation(.dsSnappy) {
                        selectedCategoryID = (selectedCategoryID == data.id) ? nil : data.id
                    }
                } label: {
                    CategoryBreakdownRow(
                        data: data,
                        fraction: vm.monthTotal > 0 ? data.amount / vm.monthTotal : 0,
                        isDimmed: selectedCategoryID != nil && selectedCategoryID != data.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "chart.pie")
                .font(.system(size: 34, relativeTo: .title))
                .foregroundStyle(DSColor.textMuted)
            Text("No expenses in \(vm.shortMonthLabel)")
                .font(.dsSubhead)
                .foregroundStyle(DSColor.textPrimary)
            Text("Add an expense or step to another month.")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.chartHeight)
        .padding(.horizontal, DSSpacing.screenEdge)
        .transition(.opacity)
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

    // MARK: - Weekly trend

    // Shares `chartReady` so the trend fades in with the rest once the present
    // transition has settled.
    @ViewBuilder
    private var weeklyTrendSection: some View {
        if chartReady {
            WeeklyTrendChartView(weeklyData: vm.weeklySpend, average: vm.weeklyAverage)
                .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Weekly trend")
                    .font(.dsSubheadSemi)
                    .foregroundStyle(DSColor.textSecondary)
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
            StatsView(transactions: transactions, categories: categories, initialMonth: Date())
        }
    }
}

#Preview {
    StatsPreviewHost()
        .modelContainer(SampleData.container())
}
