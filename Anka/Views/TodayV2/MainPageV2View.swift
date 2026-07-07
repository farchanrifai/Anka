import SwiftUI
import SwiftData

// MARK: - Main Page V2 (Experimental)
//
// App-Store-Connect-style dashboard: hero number, % change vs last period,
// fixed-width line chart with tap tooltip, icon-only view-mode picker, then
// the transaction list. Reuses `TodayViewModel` (own instance) so period
// navigation, swipe gestures, sheets, and the bottom toolbar behave exactly
// like V1 — AUDIT.md A1 (no second root view / no user-facing version
// picker). Reached via the runtime `useMainPageV2` toggle in
// Settings → Developer (see AppRouter).
struct MainPageV2View: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var vm = TodayViewModel()
    @State private var isSwitchingPeriod = false
    @State private var heroCollapsed = false
    @State private var chartMode: ChartMode = .daily

    @Namespace private var animationNamespace

    var body: some View {
        content
            .todaySheets(
                vm: vm,
                allTransactions: allTransactions,
                allCategories: allCategories,
                namespace: animationNamespace
            )
            .task(id: vm.dashboardKey) { await vm.refreshDashboard() }
            .sensoryFeedback(.selection, trigger: vm.balanceMode)
            .sensoryFeedback(.success, trigger: vm.deleteSuccessCount)
            .onAppear { feedVM() }
            .onChange(of: allTransactions) { feedVM() }
            .onChange(of: allCategories) { feedVM() }
            .onReceive(NotificationCenter.default.publisher(for: .ankaDataDidChange)) { _ in
                let fresh = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? allTransactions
                vm.update(transactions: fresh, categories: allCategories)
            }
            .inlineComposer(vm: vm)
    }

    private func feedVM() {
        vm.update(transactions: allTransactions, categories: allCategories)
    }

    // MARK: - Content

    private var content: some View {
        NavigationStack {
            scrollContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .background(DSColor.bgPrimary.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        categoryStatsButton
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        SettingsToolbarButton(vm: vm)
                    }
                    ToolbarItem(placement: .principal) {
                        heroToolbarTitle
                            .opacity(heroCollapsed ? 1 : 0)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        StatsToolbarButton(vm: vm, namespace: animationNamespace)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        FilterToolbarButton(vm: vm, namespace: animationNamespace)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        AddToolbarButton(vm: vm, namespace: animationNamespace)
                    }
                }
                .toolbarVisibility(vm.showInlineComposer ? .hidden : .visible, for: .bottomBar)
                .searchable(text: $vm.searchQuery, prompt: "Search transactions")
                .searchToolbarBehavior(.minimize)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            // Eager VStack for the top section so the anchor GeometryReader is
            // never recycled by lazy layout (LazyVStack recycles off-screen
            // items → PreferenceKey resets to defaultValue → heroCollapsed
            // toggles false while deep in the list).
            VStack(spacing: 0) {
                heroSection

                // Anchor: always rendered, tracks when hero has scrolled past
                // the top of the scroll container.
                Color.clear
                    .frame(height: 1)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: HeroOffsetKey.self,
                                value: geo.frame(in: .named("v2scroll")).minY
                            )
                        }
                    }

                chartSection

                viewModePicker
                    .padding(.horizontal, DSSpacing.screenEdge)
                    .padding(.bottom, DSSpacing.lg)
            }

            // Lazy only for the transaction list — the part that actually
            // benefits from lazy rendering.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                transactionList
                Color.clear.frame(height: 24)
            }
        }
        .coordinateSpace(name: "v2scroll")
        .onPreferenceChange(HeroOffsetKey.self) { minY in
            // The anchor sits just below the hero. When its top edge has
            // scrolled above the nav bar (~0 in scroll-content coordinates),
            // the hero is off screen → show the toolbar bubble.
            let collapsed = minY < 0
            if collapsed != heroCollapsed {
                withAnimation(.dsSnappy) { heroCollapsed = collapsed }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isSwitchingPeriod = true
                    }
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 60, abs(dx) > abs(dy) * 1.5 {
                        withAnimation(.dsSnappy) {
                            vm.navigateMonth(by: dx < 0 ? 1 : -1)
                        }
                    }
                    DispatchQueue.main.async { isSwitchingPeriod = false }
                }
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(vm.heroAmount.idrShort)
                .font(.dsHeroAmount)
                .contentTransition(.numericText(value: vm.heroAmount))
                .animation(.dsSnappy, value: vm.heroAmount)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.primary)

            if let percent = vm.previousPeriodChangePercent {
                HStack(spacing: 4) {
                    Image(systemName: percent < 0 ? "arrow.down" : "arrow.up")
                        .font(.dsCaption2Semi)
                    Text("\(abs(percent), specifier: "%.1f")% last month")
                        .font(.dsFootnoteMedium)
                }
                .foregroundStyle(DSColor.textSecondary)
            }
        }
        .opacity(heroCollapsed ? 0 : 1)
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heroToolbarTitle: some View {
        VStack(spacing: 1) {
            Text(vm.heroAmount.idrShort)
                .font(.dsFootnoteSemi)
                .contentTransition(.numericText(value: vm.heroAmount))
                .animation(.dsSnappy, value: vm.heroAmount)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Text(vm.balanceMode.title)
                    .font(.dsCaption2)
                    .foregroundStyle(DSColor.textSecondary)

                if let percent = vm.previousPeriodChangePercent {
                    Image(systemName: percent < 0 ? "arrow.down" : "arrow.up")
                        .font(.dsCaption2)
                    Text("\(abs(percent), specifier: "%.1f")%")
                        .font(.dsCaption2)
                }
            }
            .foregroundStyle(DSColor.textSecondary)
        }
        .animation(.dsSnappy, value: vm.balanceMode)
        .animation(.dsSnappy, value: vm.heroAmount)
    }

    // MARK: - Chart

    private var chartSeries: [DailySpendPoint] {
        let sorted = vm.dailySeries.sorted { $0.date < $1.date }
        guard chartMode == .cumulative else { return sorted }
        var running = 0.0
        return sorted.map {
            running += $0.total
            return DailySpendPoint(date: $0.date, total: running)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            chartModeToggle
            MainPageV2LineChart(series: chartSeries)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.bottom, DSSpacing.lg)
    }

    private var chartModeToggle: some View {
        HStack(spacing: 12) {
            ForEach(ChartMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.dsSnappy) { chartMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(chartMode == mode ? .primary : DSColor.textMuted)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(mode.rawValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Category stats shortcut

    // All 3 rectangles are 30×30 pt with cornerRadius 9 and a white stroke.
    // Left icon tilts −7° (back), right icon tilts +7° (front, drop shadow).
    // Pill height is fixed at 40pt to match the viewModePicker circle buttons below.
    @ViewBuilder
    private var categoryStatsButton: some View {
        let items = vm.topCategoryItems
        let count = vm.periodCategoryCount
        if !items.isEmpty {
            Button { vm.showStats = true } label: {
                HStack(spacing: 6) {
                    // Stacked category icons
                    ZStack(alignment: .leading) {
                        categoryBadge(items[0], rotation: -7, front: false)
                            .zIndex(0)
                        if items.count > 1 {
                            categoryBadge(items[1], rotation: 7, front: true)
                                .offset(x: 18)
                                .zIndex(1)
                        }
                    }
                    .frame(width: items.count > 1 ? 48 : 30, height: 30)

                    // "+N" — same 30×30 rect, flat
                    if count > 2 {
                        RoundedRectangle(cornerRadius: DSRadius.small)
                            .fill(DSColor.bgSecondary)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Text("+\(count - 2)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(DSColor.textPrimary)
                            }
                    }
                }
                .drawingGroup()
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .animation(.dsSnappy, value: items)
        }
    }

    private func categoryBadge(_ item: TodayViewModel.TopCategoryItem, rotation: Double, front: Bool) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.small)
            .fill(Color(hex: item.colorHex))
            .frame(width: 30, height: 30)
            .overlay { Text(item.emoji).font(.system(size: 15)) }
            .overlay {
                // Tonal separation between stacked badges (No-Shadow Rule).
                if front {
                    RoundedRectangle(cornerRadius: DSRadius.small)
                        .stroke(DSColor.bgPrimary, lineWidth: 2)
                }
            }
            .rotationEffect(.degrees(rotation))
    }

    // MARK: - View mode picker (icon-only)

    private var viewModePicker: some View {
        HStack(spacing: 8) {
            ForEach(BalanceMode.allCases, id: \.self) { mode in
                let isActive = vm.balanceMode == mode
                Button {
                    withAnimation(.dsSpring) { vm.balanceMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.dsFootnoteMedium)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                        .background(isActive ? Color.primary : DSColor.bgSecondary, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(mode.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Transaction list

    private var transactionList: some View {
        Group {
            if vm.showSkeleton {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonTransactionRow()
                }
            } else if vm.displayedGroupedByDay.isEmpty {
                TransactionEmptyStateView(
                    isUnfiltered: allTransactions.isEmpty,
                    hasActiveFilter: !vm.selectedCategories.isEmpty,
                    isSearchActive: vm.isSearchActive,
                    onAdd: { vm.showAddTransaction = true },
                    onClearFilter: { vm.clearCategoryFilter() },
                    onClearSearch: { vm.clearSearch() }
                )
            } else {
                ForEach(vm.displayedGroupedByDay, id: \.date) { group in
                    Section {
                        ForEach(group.transactions, id: \.id) { tx in
                            TransactionRow(
                                transaction: tx,
                                namespace: animationNamespace,
                                onEdit: {
                                    guard !isSwitchingPeriod else { return }
                                    vm.editingTransaction = tx
                                },
                                onDelete: { vm.requestDelete(tx) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }
                    } header: {
                        let daily = vm.dailyTotal(for: group.transactions)
                        DayHeaderView(
                            label: vm.shortDateLabel(for: group.date),
                            total: daily.amount,
                            sign: daily.sign
                        )
                    }
                }
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
    }
}

enum ChartMode: String, CaseIterable {
    case daily      = "Daily"
    case cumulative = "Cumulative"

    var icon: String {
        switch self {
        case .daily:      return "chart.bar.fill"
        case .cumulative: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Tracks the anchor view's `minY` in the scroll coordinate space so the
/// toolbar glass bubble can appear once the hero scrolls off screen.
private struct HeroOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

#Preview {
    MainPageV2View()
        .modelContainer(SampleData.container())
        .environment(CategoryPredictor())
}
