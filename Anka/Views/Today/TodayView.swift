import SwiftUI
import SwiftData

// MARK: - TodayView
//
// The Today dashboard: custom sticky header (period pill + balance-mode switcher
// + hero balance) over the day-grouped transaction list. List rows,
// empty/skeleton states, day headers, toolbar buttons, the sheet stack, and the
// V3 inline composer live in `Views/Today/Shared/`. (An experimental Mail-style
// `TodayViewV2` variant was removed — AUDIT.md A1.)

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CategoryPredictor.self) private var predictor
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    // W3: Widget deep links → open Add sheet.
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    // VM holds all state and logic
    @State private var vm = TodayViewModel()

    // View-local state (pure UI / animation — no data dependency)
    @State private var isAmountHidden  = false
    @State private var hasInitializedVisibility = false
    /// True while a horizontal month-swipe is in progress — suppresses the
    /// row tap so a swipe doesn't accidentally open a transaction.
    @State private var isSwitchingMonth = false

    @AppStorage("balanceLaunchMode") private var balanceLaunchMode = 0 // 0=Show, 1=Hide, 2=Follow Last Session
    @AppStorage("balanceLastHidden") private var balanceLastHidden = false

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
        // Modern haptics for the highest-frequency interactions. Declarative
        // `.sensoryFeedback` (no generator state to manage) and system-tuned.
        .sensoryFeedback(.selection, trigger: vm.balanceMode)
        .sensoryFeedback(.impact(weight: .light), trigger: vm.selectedMonth)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isAmountHidden)
        .sensoryFeedback(.success, trigger: vm.deleteSuccessCount)
        .onAppear {
            feedVM()
            setupAmountVisibility()
        }
        .onChange(of: isAmountHidden) { _, newValue in
            balanceLastHidden = newValue
        }
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

    private func setupAmountVisibility() {
        guard !hasInitializedVisibility else { return }
        hasInitializedVisibility = true
        switch balanceLaunchMode {
        case 1: isAmountHidden = true
        case 2: isAmountHidden = balanceLastHidden
        default: isAmountHidden = false
        }
    }

    private var dashboardTab: some View {
        NavigationStack {
            scrollContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    stickyHeader
                }
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
                // Hide the Filter/Search/Add bottom bar while the inline composer
                // is up, so it's the only bottom element (Messages-style) — and
                // the coral Add button doesn't bleed behind the glass composer.
                // `.automatic` here would let the system's own search-driven
                // bottom-bar visibility (from `.searchable` below) win, which
                // could leave the bar hidden after the composer closes until
                // some unrelated interaction forced a re-resolve. Force
                // `.visible` explicitly whenever the composer isn't up.
                .toolbarVisibility(vm.showInlineComposer ? .hidden : .visible, for: .bottomBar)
                .searchable(text: $vm.searchQuery, prompt: "Search transactions")
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
        // Belt-and-braces keyboard avoidance at the NavigationStack level too,
        // so the whole dashboard pane (not just scroll content) stays put when
        // the keyboard slides up over the search field.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
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
                                        // Ignore the tap if it was actually a month swipe.
                                        guard !isSwitchingMonth else { return }
                                        vm.editingTransaction = tx
                                    },
                                    onDelete: { vm.requestDelete(tx) }
                                )
                                // Pairs with the `withAnimation` in
                                // `refreshDashboard()` — inserted/removed rows
                                // fade + settle instead of snapping.
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
        // Horizontal swipe over the list navigates months (swipe left → next
        // month, right → previous). `.simultaneousGesture` so vertical scroll
        // and long-press context menus keep working.
        //
        // Tap-vs-swipe: as soon as a drag turns clearly horizontal we set
        // `isSwitchingMonth`, which the row's `onEdit` checks and bails on — so
        // a swipe never opens a transaction. The flag is cleared on the next
        // runloop after the gesture ends, so the row's tap (which fires on the
        // same touch-up) still sees it as `true` and is suppressed; a genuine
        // tap (no horizontal movement) never sets the flag and works normally.
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
                    // Defer so the row's tap (same touch-up) still sees the flag.
                    DispatchQueue.main.async { isSwitchingMonth = false }
                }
        )
        // Defensive — keep the ScrollView's own safe-area accounting from
        // reacting to the keyboard. The PRIMARY fix for the "UI shifted up"
        // behavior is `.searchPresentationToolbarBehavior(.avoidHidingContent)`
        // on the searchable modifier below; this one just covers the edge
        // case where the keyboard alone (no search) would still try to shrink
        // the scroll viewport.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Period + Balance Mode ──────────────────────────────────
            HStack(spacing: 8) {
                PeriodMenuPill(vm: vm)
                if !vm.isViewingCurrentMonth {
                    BackToCurrentMonthChip(vm: vm)
                }
                balanceModeSwitcher
            }
            .animation(.dsSnappy, value: vm.isViewingCurrentMonth)

            // ── Currency prefix + amount ──────────────────────────────
            HStack(alignment: .bottom, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    Text(CurrencyInfo.info(for: AppCurrency.code).symbol)
                        .font(.dsTitle2Bold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .blur(radius: isAmountHidden ? 8 : 0)

                    Text(vm.heroAmount.idrShort)
                        .font(.dsHeroAmount)
                        .contentTransition(.numericText(value: vm.heroAmount))
                        .animation(.dsSnappy, value: vm.heroAmount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.primary)
                        .blur(radius: isAmountHidden ? 16 : 0)
                }
                .onTapGesture {
                    if !vm.selectedCategories.isEmpty {
                        // Priority: clear the active category filter
                        vm.clearCategoryFilter()
                    } else {
                        // No filter active — toggle balance visibility
                        withAnimation(.dsSpring) {
                            isAmountHidden.toggle()
                        }
                    }
                }
                .allowsHitTesting(true)
                // The blur only hides the amount visually — VoiceOver would
                // still read it aloud. Mark it privacy-sensitive and swap in a
                // "Balance hidden" label so the value isn't spoken when hidden,
                // and expose the tap as an explicit a11y action (AC3).
                .privacySensitive(isAmountHidden)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isAmountHidden ? "Balance hidden" : "\(vm.balanceMode.title) balance")
                .accessibilityValue(isAmountHidden ? "" : vm.heroAmount.rupiah)
                .accessibilityHint(vm.selectedCategories.isEmpty
                    ? (isAmountHidden ? "Double tap to show the balance." : "Double tap to hide the balance.")
                    : "Double tap to clear the category filter.")
                .accessibilityAddTraits(.isButton)
            }

            // Phase 8.7: entry point to the Apple Health-style Highlights page.
            NavigationLink {
                HighlightsView(namespace: animationNamespace)
            } label: {
                HStack(spacing: 4) {
                    Text("Highlights")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.accent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                }
            }
            .matchedTransitionSource(id: "highlights", in: animationNamespace)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        // Previously 75 — that included status-bar clearance back when the nav
        // bar was fully hidden. The bar is now present (transparent), so safe
        // area already covers the status + nav bar; only breathing room left.
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let modes = BalanceMode.allCases
                    guard let idx = modes.firstIndex(of: vm.balanceMode) else { return }
                    let next = value.translation.width < 0
                        ? modes[(idx + 1) % modes.count]
                        : modes[(idx - 1 + modes.count) % modes.count]
                    withAnimation(.dsSnappyFast) { vm.balanceMode = next }
                }
        )
        .background {
            LinearGradient(
                stops: [
                    .init(color: DSColor.bgPrimary,                location: 0.0),
                    .init(color: DSColor.bgPrimary.opacity(0.99),  location: 0.6),
                    .init(color: DSColor.bgPrimary.opacity(0.93),  location: 0.8),
                    .init(color: DSColor.bgPrimary.opacity(0.465), location: 0.9),
                    .init(color: DSColor.bgPrimary.opacity(0),     location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .top)
        }
    }

    // MARK: - Balance Mode Switcher

    private var balanceModeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(BalanceMode.allCases, id: \.self) { mode in
                let isActive = vm.balanceMode == mode

                Button {
                    withAnimation(.dsSpring) {
                        vm.balanceMode = mode
                    }
                } label: {
                    HStack(spacing: isActive ? 6 : 0) {
                        Image(systemName: mode.icon)
                            .font(.dsFootnoteMedium)

                        if isActive {
                            Text(mode.title)
                                .font(.dsFootnoteMedium)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                    .background(isActive ? Color.primary : DSColor.bgSecondary, in: Capsule())
                    // Animate the pill's width as the title shows/hides, even
                    // when the mode change originates outside a withAnimation.
                    .animation(.dsSpring, value: isActive)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(SampleData.container())
        .environment(CategoryPredictor())
        .environment(DeepLinkRouter())
}
