import SwiftUI
import SwiftData

// MARK: - Dashboard scaffold
//
// Everything TodayView (V1) and MainPageV2View share, extracted verbatim so a
// dashboard fix lands in both. Three pieces:
//
//   .dashboardChrome(...)   — data plumbing: sheets, refresh task, haptics,
//                             @Query feeds, data-changed refetch, widget +
//                             auto-backup writes, deep links, inline composer.
//   .dashboardToolbar(...)  — nav-bar config + the shared toolbar (Settings /
//                             Stats / Filter / search / Add), searchable stack.
//                             Apply INSIDE the NavigationStack. A view can add
//                             its own extra `.toolbar { }` items alongside.
//   monthSwipeGesture(...)  — horizontal month navigation with tap-vs-swipe
//                             disambiguation.
//   DashboardTransactionList — skeleton / empty-state / day-grouped rows.
//
// CAUTION: the modifier ORDER in dashboardToolbar encodes iOS 26 workarounds
// (search presentation keeping content in place, forced bottom-bar visibility
// after the composer closes). Don't reorder without re-testing search + composer.

extension View {
    func dashboardChrome(
        vm: TodayViewModel,
        allTransactions: [Transaction],
        allCategories: [Category],
        namespace: Namespace.ID
    ) -> some View {
        modifier(DashboardChromeModifier(
            vm: vm,
            allTransactions: allTransactions,
            allCategories: allCategories,
            namespace: namespace
        ))
    }

    func dashboardToolbar(vm: TodayViewModel, namespace: Namespace.ID) -> some View {
        modifier(DashboardToolbarModifier(vm: vm, namespace: namespace))
    }
}

// MARK: - Chrome (data plumbing)

private struct DashboardChromeModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(CategoryPredictor.self) private var predictor
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    let vm: TodayViewModel
    let allTransactions: [Transaction]
    let allCategories: [Category]
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .todaySheets(
                vm: vm,
                allTransactions: allTransactions,
                allCategories: allCategories,
                namespace: namespace
            )
            .task(id: vm.dashboardKey) { await vm.refreshDashboard() }
            // Modern haptics for the highest-frequency interactions. Declarative
            // `.sensoryFeedback` (no generator state to manage) and system-tuned.
            .sensoryFeedback(.selection, trigger: vm.balanceMode)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.selectedMonth)
            .sensoryFeedback(.success, trigger: vm.deleteSuccessCount)
            .onAppear { feedVM() }
            .onChange(of: allTransactions) {
                feedVM()
                WidgetDataWriter.shared.updateWidgetData(transactions: allTransactions)
            }
            .onChange(of: allCategories) { feedVM() }
            .autoBackup(transactions: allTransactions, categories: allCategories)
            // W3: Widget deep links — open the Add sheet when `anka://add` arrives.
            .onChange(of: deepLinkRouter.pendingAddTransaction) { _, pending in
                guard pending else { return }
                deepLinkRouter.pendingAddTransaction = false
                vm.showAddTransaction = true
            }
            // X2: Central data-changed hook. `onChange(of: allTransactions)` misses
            // in-place edits (same @Model identities → array compares equal) and
            // Settings-side import/restore. On the notification, re-fetch the
            // authoritative list so the dashboard + widgets always reflect reality.
            .onReceive(NotificationCenter.default.publisher(for: .ankaDataDidChange)) { _ in
                let fresh = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? allTransactions
                vm.update(transactions: fresh, categories: allCategories)
                WidgetDataWriter.shared.updateWidgetData(transactions: fresh)
            }
            // V3 Liquid Glass inline composer — rides the keyboard (not a sheet).
            .inlineComposer(vm: vm)
    }

    private func feedVM() {
        vm.update(transactions: allTransactions, categories: allCategories)
        predictor.updateRecentAmounts(allTransactions.filter { $0.type == .expense }.map(\.amount))
    }
}

// MARK: - Toolbar + search (apply inside the NavigationStack)

private struct DashboardToolbarModifier: ViewModifier {
    let vm: TodayViewModel
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(DSColor.bgPrimary.ignoresSafeArea())
            // Bottom toolbar: Stats • Filter • search (minimized) • Add.
            // Settings stays in the top bar.
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SettingsToolbarButton(vm: vm)
                }

                ToolbarItem(placement: .bottomBar) {
                    StatsToolbarButton(vm: vm, namespace: namespace)
                }
                ToolbarItem(placement: .bottomBar) {
                    FilterToolbarButton(vm: vm, namespace: namespace)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    AddToolbarButton(vm: vm, namespace: namespace)
                }
            }
            // Hide the Filter/Search/Add bottom bar while the inline composer
            // is up, so it's the only bottom element (Messages-style) — and
            // the coral Add button doesn't bleed behind the glass composer.
            // `.automatic` here would let the system's own search-driven
            // bottom-bar visibility (from `.searchable` below) win, which
            // could leave the bar hidden after the composer closes until
            // some unrelated interaction forced a re-resolve. Force
            // `.visible` explicitly whenever the composer isn't up.
            .toolbarVisibility(vm.showInlineComposer ? .hidden : .visible, for: .bottomBar)
            .searchable(text: Bindable(vm).searchQuery, prompt: "Search transactions")
            .searchToolbarBehavior(.minimize)
            // CRITICAL: iOS 26's default search-presentation behavior hides
            // the underlying content (nav bar + sticky header + scroll
            // content slide up out of view) when the search field becomes
            // active — that's the "UI shifted up" symptom. `.ignoresSafeArea(.keyboard)`
            // doesn't help because this isn't keyboard avoidance, it's
            // UISearchController's hidesNavigationBarDuringPresentation +
            // standard search-active animation. This modifier (iOS 18.2+)
            // tells the search presentation to keep the underlying content
            // in place.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
    }
}

// MARK: - Month swipe gesture

/// Horizontal swipe over the list navigates months (swipe left → next month,
/// right → previous). Attach with `.simultaneousGesture` so vertical scroll
/// and long-press context menus keep working.
///
/// Tap-vs-swipe: as soon as a drag turns clearly horizontal we set
/// `isSwitching`, which the row's `onEdit` checks and bails on — so a swipe
/// never opens a transaction. The flag is cleared on the next runloop after
/// the gesture ends, so the row's tap (which fires on the same touch-up)
/// still sees it as `true` and is suppressed; a genuine tap (no horizontal
/// movement) never sets the flag and works normally.
@MainActor
func monthSwipeGesture(vm: TodayViewModel, isSwitching: Binding<Bool>) -> some Gesture {
    DragGesture(minimumDistance: 18)
        .onChanged { value in
            if abs(value.translation.width) > abs(value.translation.height) {
                isSwitching.wrappedValue = true
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
            // Defer so the row's tap (same touch-up) still sees the flag.
            DispatchQueue.main.async { isSwitching.wrappedValue = false }
        }
}

// MARK: - Transaction list

/// The day-grouped transaction list shared by both dashboards: skeleton rows
/// on cold start, tailored empty states, otherwise pinned day sections. Embed
/// inside a `LazyVStack(pinnedViews: .sectionHeaders)`.
struct DashboardTransactionList: View {
    let vm: TodayViewModel
    let allTransactionsEmpty: Bool
    let namespace: Namespace.ID
    /// Read at tap time — suppresses row taps during a month swipe.
    let isSwitching: () -> Bool

    var body: some View {
        if vm.showSkeleton {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonTransactionRow()
            }
        } else if vm.displayedGroupedByDay.isEmpty {
            TransactionEmptyStateView(
                isUnfiltered: allTransactionsEmpty,
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
                            namespace: namespace,
                            onEdit: {
                                // Ignore the tap if it was actually a month swipe.
                                guard !isSwitching() else { return }
                                vm.editingTransaction = tx
                            },
                            onDelete: { vm.requestDelete(tx) }
                        )
                        // Pairs with the `withAnimation` in `refreshDashboard()`
                        // — inserted/removed rows fade + settle instead of snapping.
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
}
