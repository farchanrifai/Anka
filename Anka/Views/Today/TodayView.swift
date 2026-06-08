import SwiftUI
import SwiftData

// MARK: - Scroll Offset PreferenceKey

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - TodayView

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    // VM holds all state and logic
    @State private var vm = TodayViewModel()

    // View-local state (pure UI / animation — no data dependency)
    @State private var scrollOffset: CGFloat = 0
    @State private var isAmountHidden  = false
    @State private var hasInitializedVisibility = false

    @AppStorage("balanceLaunchMode") private var balanceLaunchMode = 0 // 0=Show, 1=Hide, 2=Follow Last Session
    @AppStorage("balanceLastHidden") private var balanceLastHidden = false

    @Namespace private var animationNamespace

    // MARK: - Body

    var body: some View {
        dashboardTab
        .sheet(isPresented: $vm.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $vm.showAddTransaction) {
            AddTransactionView(defaultType: vm.addDefaultType)
                .navigationTransition(.zoom(sourceID: "addTransaction", in: animationNamespace))
        }
        .sheet(isPresented: $vm.showCategoryFilter) {
            CategoryFilterSheet(selection: $vm.selectedCategories)
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
        .onChange(of: vm.selectedCategories) { _, _ in
            vm.onCategoryFilterChanged(scrollOffset: scrollOffset)
        }
        .task(id: vm.dashboardKey) { await vm.refreshDashboard() }
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
                // Keep the nav bar present (but invisible) so pushing Stats
                // crossfades the back button in place — matching the iOS
                // Settings app — instead of sliding a fresh bar in with the
                // pushed view.
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .background(DSColor.bgPrimary.ignoresSafeArea())
                // iOS Mail-style bottom toolbar: Filter • Search • Add.
                // Layout switches on filter state:
                //   - inactive: filter-icon | flex | full search bar | flex | +
                //   - active:   filter-pill | flex | search-circle | +
                // (when active the trailing flex is dropped so the search
                //  circle sits right next to + with standard toolbar padding.)
                // Settings lives in the top-bar trailing slot so it crossfades
                // out (iOS Settings-style) when Stats is pushed.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { settingsToolbarButton }

                    ToolbarItem(placement: .bottomBar) { filterToolbarButton }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    if vm.filterLabel == nil {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                    }
                    ToolbarItem(placement: .bottomBar) { addToolbarButton }
                }
                .searchable(text: $vm.searchQuery, prompt: "Search transactions")
                // Only force the search to its minimized magnifying-glass
                // circle when the Filter pill is wide. When inactive let the
                // bar expand to fill the centre — matching Mail.
                .searchToolbarBehavior(vm.filterLabel == nil ? .automatic : .minimize)
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
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: -geo.frame(in: .named("dashScroll")).minY
                    )
                }
                .frame(height: 0)

                // Bar chart hidden for now.

                if vm.isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        skeletonTransactionRow
                    }
                } else if vm.displayedGroupedByDay.isEmpty {
                    emptyStateView
                } else {
                    ForEach(vm.displayedGroupedByDay, id: \.date) { group in
                        Section {
                            ForEach(group.transactions, id: \.id) { tx in
                                transactionRow(tx)
                            }
                        } header: {
                            dayHeader(for: group)
                        }
                    }
                }

                Color.clear.frame(height: 24)
            }
        }
        .coordinateSpace(name: "dashScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            scrollOffset = offset       // view owns the raw offset (presentational)
            vm.handleScrollOffset(offset) // VM derives isChartVisible from it
        }
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
            // ── Expense / Income / Total switcher ─────────────────────
            balanceModeSwitcher

            // ── Currency prefix + amount ──────────────────────────────
            HStack(alignment: .bottom, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp")
                        .font(.dsTitle2Bold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .blur(radius: isAmountHidden ? 8 : 0)

                    Text(vm.heroAmount.idrShort)
                        .font(.system(size: 52, weight: .black))
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

            // ── Period indicator + Navigate to Reports ─────────────────
            HStack(alignment: .center, spacing: 0) {
                periodIndicator
                Spacer()
                statsButton
            }
        }
        .padding(.horizontal, 20)
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

    // MARK: - Period Indicator

    private var periodIndicator: some View {
        Menu {
            ForEach(PeriodFilter.allCases, id: \.self) { period in
                Button(period.displayString) { vm.selectedPeriod = period }
            }
        } label: {
            HStack(spacing: 4) {
                let displayText = vm.selectedPeriod.displayString
                let capitalizedText = displayText.prefix(1).uppercased() + displayText.dropFirst()
                Text(capitalizedText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsBadgeSemi)
            }
            .font(.dsFootnoteMedium)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Balance Mode Switcher

    private var balanceModeSwitcher: some View {
        HStack(spacing: 16) {
            ForEach(BalanceMode.allCases, id: \.self) { mode in
                Text(mode.title)
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(vm.balanceMode == mode ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) { vm.balanceMode = mode }
                    }
            }
        }
    }

    // MARK: - Stats Button

    private var statsButton: some View {
        NavigationLink {
            StatsView()
        } label: {
            HStack(spacing: 4) {
                Text("Stats")
                Image(systemName: "arrow.right")
            }
            .font(.dsFootnoteMedium)
            .foregroundStyle(DSColor.accent)
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(vm.chartData.enumerated()), id: \.element.category.id) { index, item in
                    let isMax = index == 0
                    let maxTotal = vm.chartData.first?.total ?? 1
                    let barHeight = max(45, CGFloat(item.total / maxTotal) * 200)
                    chartColumn(category: item.category, total: item.total, barHeight: barHeight, isMax: isMax)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chartColumn(
        category: Category, total: Double, barHeight: CGFloat, isMax: Bool
    ) -> some View {
        Button {
            vm.addCategory(category)
        } label: {
            ZStack(alignment: .bottom) {
                Color.clear.frame(width: 72, height: 200)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isMax ? Color.primary.opacity(0.25) : Color.primary.opacity(0.12))

                    VStack(spacing: 2) {
                        Text(category.emoji)
                            .font(.dsTitle3)
                        Text(vm.abbreviatedAmount(total))
                            .font(.dsCaption2Bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
                .frame(width: 72, height: barHeight)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: allTransactions.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.primary, in: Capsule())
                }
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
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
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
        .padding(.horizontal, 20)
        .frame(height: 68)
        .redacted(reason: .placeholder)
    }

    // MARK: - Transaction Row

    private func transactionRow(_ tx: Transaction) -> some View {
        Button {
            vm.editingTransaction = tx
        } label: {
            HStack(spacing: 12) {
                let cat = tx.category
                ZStack {
                    Circle()
                        .fill((cat.map { Color(hex: $0.colorHex) } ?? .gray).opacity(0.15))
                        .frame(width: 54, height: 54)
                    Text(cat?.emoji ?? "💳")
                        .font(.system(size: 24))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(cat?.name ?? "Uncategorized")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)

                    let desc = tx.note?.isEmpty == false ? tx.note! : (cat?.name ?? tx.type.displayName)
                    Text(desc)
                        .font(.dsBodySemi)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                let sign = tx.type == .expense ? "" : "+ "
                Text("\(sign)Rp \(tx.amount.idrShort)")
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DSColor.bgSecondary, in: Capsule())
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        // Mail-like zoom: tapping a row presents the edit sheet via a zoom
        // transition originating from this row. Pairs with
        // `.navigationTransition(.zoom(sourceID: tx.id, in: animationNamespace))`
        // applied on the edit sheet's AddTransactionView. Each row uses its
        // own tx.id so the zoom sources from the exact row the user tapped.
        .matchedTransitionSource(id: tx.id, in: animationNamespace)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { vm.requestDelete(tx) } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
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
