import SwiftUI
import SwiftData

// MARK: - TodayViewV2 (testing)
//
// Experimental variant of TodayView that replaces the custom sticky header
// with a Mail-app-style collapsing large title:
//   - Hero number (the balance) as the navigation large title
//   - Period indicator (e.g. "June") as the navigation subtitle, mirroring
//     "Checking for Mail..."
//   - Expense/Income/Total selector styled like Mail's category pill row,
//     scrolling away with the content
//   - When scrolled, the subtitle becomes "Period · Mode" (e.g.
//     "June · Expense"), mirroring Mail's collapsed "Primary · Checking for…"
//
// The transaction list, skeleton/empty states, day headers, toolbar items, and
// sheet stack are shared with TodayView via the components in
// `Views/Today/Shared/`.

struct TodayViewV2: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    // W3: Widget deep links → open Add sheet.
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var vm = TodayViewModel()

    /// True while a horizontal month-swipe is in progress — suppresses the
    /// row tap so a swipe doesn't accidentally open a transaction.
    @State private var isSwitchingMonth = false

    /// Tracks whether the large title has collapsed into the compact nav bar,
    /// driving the "Period · Mode" subtitle (Mail's "Primary · Checking for…").
    @State private var isCollapsed = false

    @Namespace private var animationNamespace

    // MARK: - Body

    var body: some View {
        dashboardTab
        .todaySheets(
            vm: vm,
            allTransactions: allTransactions,
            allCategories: allCategories,
            namespace: animationNamespace
        )
        .task(id: vm.dashboardKey) { await vm.refreshDashboard() }
        .sensoryFeedback(.selection, trigger: vm.balanceMode)
        .sensoryFeedback(.impact(weight: .light), trigger: vm.selectedMonth)
        .sensoryFeedback(.success, trigger: vm.deleteSuccessCount)
        .onAppear { feedVM() }
        .onChange(of: allTransactions) {
            feedVM()
            WidgetDataWriter.shared.updateWidgetData(transactions: allTransactions)
        }
        .onChange(of: allCategories) {
            feedVM()
        }
        .autoBackup(transactions: allTransactions, categories: allCategories)
        // W3: Widget deep links — open the Add sheet when `anka://add` arrives.
        .onChange(of: deepLinkRouter.pendingAddTransaction) { _, pending in
            guard pending else { return }
            deepLinkRouter.pendingAddTransaction = false
            vm.showAddTransaction = true
        }
        // X2: Central data-changed hook — re-fetch on mutations that don't change
        // the @Query array identity (in-place edits, import, restore).
        .onReceive(NotificationCenter.default.publisher(for: .ankaDataDidChange)) { _ in
            let fresh = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? allTransactions
            vm.update(transactions: fresh, categories: allCategories)
            WidgetDataWriter.shared.updateWidgetData(transactions: fresh)
        }
    }

    private func feedVM() {
        vm.update(transactions: allTransactions, categories: allCategories)
    }

    // MARK: - Dashboard

    private var dashboardTab: some View {
        NavigationStack {
            scrollContent
                .background(DSColor.bgPrimary.ignoresSafeArea())
                // Mail-style collapsing large title: hero number large, period
                // indicator as subtitle. When scrolled the subtitle gains the
                // active Expense/Income/Total mode, mirroring Mail's
                // "Primary · Checking for…".
                .navigationTitle(heroTitleText)
                .navigationBarTitleDisplayMode(.large)
                .navigationSubtitle(subtitleText)
                .toolbar {
                    // Left-aligns the collapsed nav-bar title/subtitle (the
                    // system's default inline title is centered). Only
                    // visible once the large title has collapsed — the
                    // principal item doesn't render while the large title
                    // is showing.
                    ToolbarItem(placement: .principal) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(heroTitleText)
                                .font(.dsHeadlineSemi)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(subtitleText)
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        StatsToolbarButton(vm: vm, namespace: animationNamespace)
                        SettingsToolbarButton(vm: vm)
                    }

                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        FilterToolbarButton(vm: vm, namespace: animationNamespace)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        AddToolbarButton(vm: vm, namespace: animationNamespace)
                    }
                }
                .searchable(text: $vm.searchQuery, prompt: "Search transactions")
                .searchToolbarBehavior(.minimize)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// "Rp 1,234,567" — the hero number, shown as the large title (Mail's
    /// "All Inboxes").
    private var heroTitleText: String {
        vm.heroAmount.rupiah
    }

    /// "June" while expanded; "June · Expense" once collapsed — mirrors
    /// Mail's "Checking for Mail..." → "Primary · Checking for...".
    private var subtitleText: String {
        isCollapsed ? "\(vm.periodPillLabel) · \(vm.balanceMode.title)" : vm.periodPillLabel
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                modeSelectorPills
                    .padding(.horizontal, DSSpacing.screenEdge)
                    .padding(.bottom, 12)

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
                                        guard !isSwitchingMonth else { return }
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

                Color.clear.frame(height: 24)
            }
        }
        // Drives the collapsed-subtitle state — once the content has scrolled
        // past the large title, switch to the compact "Period · Mode" form.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 8
        } action: { _, collapsed in
            withAnimation(.dsEase) {
                isCollapsed = collapsed
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isSwitchingMonth = true
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
                    DispatchQueue.main.async { isSwitchingMonth = false }
                }
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Mode selector pills (Mail category-pill row equivalent)

    private var modeSelectorPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PeriodMenuPill(vm: vm)
                if !vm.isViewingCurrentMonth {
                    BackToCurrentMonthChip(vm: vm)
                }

                ForEach(BalanceMode.allCases, id: \.self) { mode in
                    let isActive = vm.balanceMode == mode

                    Button {
                        withAnimation(.dsSpring) {
                            vm.balanceMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.dsFootnoteMedium)
                            Text(mode.title)
                                .font(.dsFootnoteMedium)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                        .background(isActive ? Color.primary : DSColor.bgSecondary, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 4)
            .animation(.dsSnappy, value: vm.isViewingCurrentMonth)
        }
    }
}

#Preview {
    TodayViewV2()
        .modelContainer(SampleData.container())
        .environment(CategoryPredictor())
        .environment(DeepLinkRouter())
}
