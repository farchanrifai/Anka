import SwiftUI
import SwiftData

// MARK: - TodayView

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

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
        .sheet(isPresented: $vm.showStats) {
            StatsView(transactions: allTransactions, categories: allCategories)
        }
        .sheet(isPresented: $vm.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $vm.showAddTransaction) {
            AddTransactionView(defaultType: vm.addDefaultType)
                .navigationTransition(.zoom(sourceID: "addTransaction", in: animationNamespace))
        }
        .sheet(isPresented: $vm.showCategoryFilter) {
            CategoryFilterSheet(
                selection: $vm.selectedCategories,
                selectedPeriod: $vm.selectedPeriod,
                customStartDate: $vm.customStartDate,
                customEndDate: $vm.customEndDate
            )
            .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // Zoom transition originates from the filter toolbar button.
                // The detent (.medium default, .large via drag) is honored —
                // the zoom destination is whatever final size the sheet
                // settles at, so this Mail-style expansion still resolves to
                // a half-page sheet.
                .navigationTransition(.zoom(sourceID: "filter", in: animationNamespace))
        }
        .sheet(isPresented: Binding(
            get: { vm.editingTransaction != nil },
            set: { if !$0 { vm.editingTransaction = nil } }
        )) {
            if let tx = vm.editingTransaction {
                AddTransactionView(defaultType: tx.type, existingTransaction: tx)
                    .navigationTransition(.zoom(sourceID: tx.id, in: animationNamespace))
            }
        }
        .alert("Delete Transaction?", isPresented: Binding(
            get: { vm.pendingDeleteTransaction != nil },
            set: { if !$0 { vm.pendingDeleteTransaction = nil } }
        )) {
            Button("Delete", role: .destructive) { vm.confirmDelete(context: modelContext) }
            Button("Cancel", role: .cancel) { vm.pendingDeleteTransaction = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { vm.deleteErrorMessage != nil },
            set: { if !$0 { vm.deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.deleteErrorMessage = nil }
        } message: {
            Text(vm.deleteErrorMessage ?? "An unknown error occurred. Please try again.")
        }
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
    }

    private func feedVM() {
        vm.update(transactions: allTransactions, categories: allCategories)
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
                // iOS Mail-style bottom toolbar: Filter • Search • Add.
                // Layout switches on filter state:
                //   - inactive: filter-icon | flex | full search bar | flex | +
                //   - active:   filter-pill | flex | search-circle | +
                // (when active the trailing flex is dropped so the search
                //  circle sits right next to + with standard toolbar padding.)
                // Stats + Settings present as sheets (not pushes) so they don't
                // contend with the bottom-bar search item for the Liquid Glass
                // toolbar's trailing item group — that contention is what caused
                // the empty-glass-capsule freeze (`glassEffect() tried to update
                // multiple times per frame`).
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        statsToolbarButton
                        settingsToolbarButton
                    }

                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { filterToolbarButton }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { addToolbarButton }
                }
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

    // MARK: - Bottom toolbar buttons

    @ViewBuilder
    private var filterToolbarButton: some View {
        Button {
            vm.showCategoryFilter = true
        } label: {
            if let label = vm.filterLabel {
                // Active state: icon + "Filtered by <label> ⌄"
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Filtered by")
                            .font(.dsCaption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Text(label)
                                .font(.dsFootnoteSemi)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.dsCaption2Semi)
                        }
                    }
                }
            } else {
                // Idle state: just the icon, system renders it as a circle.
                Image(systemName: "line.3.horizontal.decrease")
            }
        }
        .tint(vm.filterLabel == nil ? .primary : DSColor.accent)
        .accessibilityLabel(vm.filterLabel == nil ? "Filter" : "Filtered by \(vm.filterLabel!). Tap to edit.")
        // Mail-style zoom: sheet expands out of the filter button. Detent
        // is preserved on the sheet side (`.medium` default).
        .matchedTransitionSource(id: "filter", in: animationNamespace)
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            vm.showAddTransaction = true
        } label: {
            Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("Add transaction")
        .matchedTransitionSource(id: "addTransaction", in: animationNamespace)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                if vm.showSkeleton {
                    ForEach(0..<5, id: \.self) { _ in
                        skeletonTransactionRow
                    }
                } else if vm.displayedGroupedByDay.isEmpty {
                    emptyStateView
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
                            dayHeader(for: group)
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
                        withAnimation(.snappy(duration: 0.3)) {
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
                periodPill
                balanceModeSwitcher
            }

            // ── Currency prefix + amount ──────────────────────────────
            HStack(alignment: .bottom, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp")
                        .font(.dsTitle2Bold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .blur(radius: isAmountHidden ? 8 : 0)

                    Text(vm.heroAmount.idrShort)
                        .font(.dsHeroAmount)
                        .contentTransition(.numericText(value: vm.heroAmount))
                        .animation(.snappy(duration: 0.3), value: vm.heroAmount)
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isAmountHidden.toggle()
                        }
                    }
                }
                .allowsHitTesting(true)
            }
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
                    withAnimation(.snappy(duration: 0.25)) { vm.balanceMode = next }
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


    // MARK: - Period Pill

    private var periodPill: some View {
        Button {
            vm.showCategoryFilter = true
        } label: {
            Text(vm.periodPillLabel)
                .font(.dsFootnoteMedium)
                .lineLimit(1)
                // Roll the label like the hero number when the month changes.
                .contentTransition(.numericText())
                // Match the mode-picker pills exactly: same padding + Capsule radius.
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(DSColor.textOnAccent)
                .background(DSColor.accent, in: Capsule())
                // Animate both the label transition and the pill's width as the
                // text length changes (e.g. "May" → "September" → "3 Months").
                .animation(.snappy(duration: 0.3), value: vm.periodPillLabel)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Period: \(vm.periodPillLabel). Tap to change.")
    }

    // MARK: - Balance Mode Switcher

    private var balanceModeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(BalanceMode.allCases, id: \.self) { mode in
                let isActive = vm.balanceMode == mode
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    .padding(.horizontal, isActive ? 14 : 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                    .background(isActive ? Color.primary : DSColor.bgSecondary, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: - Stats Toolbar Button

    private var statsToolbarButton: some View {
        Button { vm.showStats = true } label: {
            Image(systemName: "chart.pie")
        }
        .tint(.primary)
        .accessibilityLabel("Stats")
    }

    // MARK: - Day Header

    private func dayHeader(for group: (date: Date, transactions: [Transaction])) -> some View {
        let dailyTotal: Double
        let sign: String
        switch vm.balanceMode {
        case .expense:
            dailyTotal = group.transactions.reduce(0) { $0 + $1.amount }
            sign = ""
        case .income:
            dailyTotal = group.transactions.reduce(0) { $0 + $1.amount }
            sign = "+"
        case .total:
            let net = group.transactions.reduce(0) { $0 + ($1.type == .income ? $1.amount : -$1.amount) }
            dailyTotal = abs(net)
            sign = net >= 0 ? "+" : "-"
        }

        return HStack {
            Text(vm.shortDateLabel(for: group.date))
                .font(.dsFootnoteMedium)
                .foregroundStyle(.primary)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            if dailyTotal > 0 {
                Text("\(sign)Rp \(dailyTotal.idrShort)")
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(.primary)
                    .frame(height: 28)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: allTransactions.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                // Subtle one-shot bounce when the empty state (re)appears —
                // softens the "nothing here" moment without looping motion.
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.bottom, 4)

            VStack(spacing: 4) {
                Text(allTransactions.isEmpty ? "No Transactions Yet" : "No Matches Found")
                    .font(.dsHeadlineSemi)
                    .foregroundStyle(.primary)

                Text(allTransactions.isEmpty ? "Tap the button below to add your first expense or income." : "No transactions match the selected period or filters.")
                    .font(.dsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if allTransactions.isEmpty {
                Button {
                    vm.showAddTransaction = true
                } label: {
                    Text("Add Transaction")
                        .font(.dsSubheadSemi)
                        .foregroundStyle(DSColor.bgPrimary)
                        .padding(.horizontal, DSSpacing.screenEdge)
                        .padding(.vertical, 10)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
            } else if !vm.selectedCategories.isEmpty {
                Button {
                    vm.clearCategoryFilter()
                } label: {
                    Text("Clear Filters")
                        .font(.dsBodyMedium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DSColor.bgSecondary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Skeleton Row (shown while refreshDashboard is running)

    private var skeletonTransactionRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 27)
                .fill(DSColor.bgSecondary)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DSColor.bgSecondary)
                    .frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(DSColor.bgSecondary)
                    .frame(width: 120, height: 12)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 12)
                .fill(DSColor.bgSecondary)
                .frame(width: 64, height: 28)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .frame(height: 68)
        .redacted(reason: .placeholder)
    }

    // MARK: - Settings Button

    private var settingsToolbarButton: some View {
        Button { vm.showSettings = true } label: {
            Image(systemName: "gearshape")
        }
        .tint(.primary)
        .accessibilityLabel("Settings")
    }
}

#Preview {
    TodayView()
        .modelContainer(SampleData.container())
        .environment(CategoryPredictor())
}
