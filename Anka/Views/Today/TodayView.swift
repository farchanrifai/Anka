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
        .dashboardChrome(
            vm: vm,
            allTransactions: allTransactions,
            allCategories: allCategories,
            namespace: animationNamespace
        )
        // V1-only: hide/show-balance haptic + launch visibility preference.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isAmountHidden)
        .onAppear { setupAmountVisibility() }
        .onChange(of: isAmountHidden) { _, newValue in
            balanceLastHidden = newValue
        }
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
                .dashboardToolbar(vm: vm, namespace: animationNamespace)
        }
        // Belt-and-braces keyboard avoidance at the NavigationStack level too,
        // so the whole dashboard pane (not just scroll content) stays put when
        // the keyboard slides up over the search field.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                DashboardTransactionList(
                    vm: vm,
                    allTransactionsEmpty: allTransactions.isEmpty,
                    namespace: animationNamespace,
                    isSwitching: { isSwitchingMonth }
                )

                Color.clear.frame(height: 24)
            }
        }
        .simultaneousGesture(monthSwipeGesture(vm: vm, isSwitching: $isSwitchingMonth))
        // Defensive — keep the ScrollView's own safe-area accounting from
        // reacting to the keyboard. The PRIMARY fix for the "UI shifted up"
        // behavior is `.searchPresentationToolbarBehavior(.avoidHidingContent)`
        // in the shared dashboardToolbar; this one just covers the edge
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
                        .font(.dsCaptionSemi)
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
        BalanceModePicker(mode: $vm.balanceMode)
    }
}

#Preview {
    TodayView()
        .modelContainer(SampleData.container())
        .environment(CategoryPredictor())
        .environment(DeepLinkRouter())
}
