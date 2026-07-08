# Anka Full-App Audit & Rework Plan

## Status (2026-07-08) — ALL PHASES COMPLETE

| Phase | Commit | Notes |
|---|---|---|
| 1 Dead code + hygiene | `2f1cd27` | Week-helper cluster deleted too (startOfWeek/weekInterval/weekLabel/formatWeekRange were also dead) |
| 2 DS components + font sweep | `5c07eb2` | 30 sites fixed (list had 29 + AnkaApp:204); helper gained `design:` param |
| 3 Performance | `200427a` | 3a–3d done; 3e skipped (see below); VM's `availableCategories`/public `filteredTransactions` were dead → deleted, not cached |
| 4 Dashboard scaffold | `ba611a8` | V2 gained widget/backup/deep-link/haptics/predictor-feed for free; verified both dashboards in simulator |
| 5 Unified edit flow | `dc6634a` | Edit sheet gained tag row; zoom transition kept on edit sheet |
| 6 AddTransaction decomposition | `2b65a83` | New `dsMorph` token; sparkle 4→2 stacked animations; Save-button zero-width collapse kept (documented, deliberate) |
| 7 Visual pass | `ed3c86c` | 7a done; 7b (V1 collapsing header) dropped — safeAreaInset height animation feeds back into scroll insets; 7c/7d already conformant after 2+6 |
| 8 Tests | `f920240` | 94 tests / 13 suites green (was 76/10) |

Note: `graphify` CLI is not installed on this machine — `graphify update .` could not be run after changes.

## Context

Anka: single-user iOS 26 expense tracker (SwiftData, @Observable, Liquid Glass, DS tokens). Full audit ran across architecture, UI/UX, animations, and debt. Foundation is disciplined (real token system, Dynamic Type via DSFont, modern haptics, good a11y), but debt is concentrated in: uncached O(n) ViewModel work on main, ~29 Dynamic-Type-breaking fonts, duplicated V1/V2 dashboard scaffold, triplicated components, animation-token drift in AddTransactionView (764-line monolith), dead chart code, and zero tests on security-critical AppLock code.

User decisions (fixed):
- **Keep both dashboards** (TodayView + MainPageV2View behind `useMainPageV2`), extract shared scaffold to kill duplication.
- **Fresh visual pass allowed** within DESIGN.md language.
- **Launch blockers** (icon, StoreKit, localization) **out of scope**.
- **Unify edit flow**: always compact `EditTransactionSheet` (gains tag support); AddTransactionView becomes add-only.

Note: graphify CLI is not installed on this machine (`command not found`) — skip `graphify update .` steps; flag to user.

Build/verify after every phase:
```
xcodebuild -project Anka.xcodeproj -scheme Anka -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -project Anka.xcodeproj -scheme Anka -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -only-testing:AnkaTests
```

---

## Phase 1 — Dead code + mechanical hygiene (zero-risk)

**Delete** (confirmed unreferenced):
- `Anka/Views/Stats/WeeklyTrendChartView.swift`
- `Anka/Models/WeeklySpendData.swift`
- `weekEndRange` in `Anka/DesignSystem/DateHelpers.swift:95`
- Remove from project.pbxproj (check if project uses file-system-synchronized groups — objectVersion 77 — deletion may be automatic).

**Edit:**
- `Services/CategoryPredictor.swift:133,146,152` — `print()` → `os.Logger` (one static logger).
- `Views/TodayV2/MainPageV2View.swift:11` — fix false "DEBUG only" header comment (toggle is runtime).
- Delete two forbidden `.shadow()`: `MainPageV2View.swift:301` (badge stack — rotation+zIndex already conveys depth; add 2pt `bgPrimary` stroke if separation lost) and `DateRangePicker.swift:229`.
- Haptics: `DonutChartView.swift:33,164`, `DateRangePicker.swift:243-245` — imperative `UIImpactFeedbackGenerator` → `.sensoryFeedback(.impact, trigger:)` matching TodayView pattern.
- `Components/AmountLabel.swift:24` — `0.12` → DSOpacity token (add if absent).
- Hardcoded radii: `AddTransactionView.swift:313,314,429,430` `999` → `DSRadius.full`; `MainPageV2View.swift:277,296` `9` → nearest token; `BackupSettingsView.swift:374` `18` → nearest token.

**Verify:** build + unit tests; haptics feel-check in simulator.

## Phase 2 — Design-system components + token sweep

**New `Anka/Components/Card.swift`:** dumb surface wrapper — `bgCard`, `DSRadius.large`, `DSSpacing.md` padding, no border/shadow. Plus `.dsChip(active:)` view extension (capsule, bgSecondary idle / accent active). Root-cause fix for per-screen surface re-rolling.

**New `Anka/Components/BalanceModePicker.swift`:** extract triplicated switcher (`TodayView.swift:356-387`, `StatsView.swift:132-158`, `MainPageV2View.swift:306-324`). API: `@Binding var mode` + `iconOnly: Bool` (V2 circle variant). Replace all three call sites.

**Font sweep:** fix all ~29 `.font(.system(size:))` without `relativeTo:` — map to existing DSFont tokens where possible; add `DSFont.dsScaled(_:weight:relativeTo:)` helper for odd sizes (AppLock PIN dots). Sites: AppLockView (33,149,183,252), PINSetupSheet (33,51), AddTransactionView (249,258,487,572,616,635), MainPageV2View (241,282,299), SettingsView:108, AddEditCategorySheet:88, BackupSettingsView (300,325), CategoryManagementView (128,137), CurrencySettingsView:56, AppearanceSettingsView (68,98), ImportPreviewSheet (146-158).

**Padding sweep:** raw paddings → nearest DSSpacing at clear-violation sites only (e.g. `TodayView.swift:376`, `StatsView.swift:148`).

**Adopt Card/chip:** AddTransactionView chips (:313-314), Highlights cards (Daily/Weekly/Monthly/TopCategory).

**Verify:** build; dark+light screenshots; Dynamic Type at Accessibility XXL on AppLock + Add screens.

## Phase 3 — Performance (`TodayViewModel.swift` unless noted)

**3a. Cache hot computed properties** — convert to `private(set) var` stored fields written only in `refreshDashboard()`: `expenseTotal`, `incomeTotal`, `heroAmount`, `filteredTransactions`, `topCategoryItems`, `periodCategoryCount`, `availableCategories`. Safe: `dashboardKey` (:139-148) already encodes every input incl. `dataVersion`; `.task(id:)` re-fires on any change. Heavy math moves into existing `Task.detached` block; `availableCategories` stays on main (cheap).

**3b. Snapshot/dictionary cost** — cache `[TransactionSnapshot]` keyed on `dataVersion` (skip O(n) re-map on month swipes/mode toggles); scope the merge Dictionary (:483) to period IDs instead of all transactions.

**3c. `Services/WidgetDataWriter.swift`** — map to Sendable DTOs on main, filter/reduce/encode/write in `Task.detached(.utility)`, then `reloadAllTimelines()`. Add ~1s trailing debounce (stored cancellable Task) so change bursts produce one write.

**3d. `Services/AutoBackupService.swift:88-92` + `BackupService.swift`** — split export into `makeDTO` (on main, touches @Model) + `encode` (pure, moves into existing detached write task).

**3e. `Services/CategoryPredictor.swift`** — SKIPPED (decided during implementation): inference is a single short-string NLModel lookup (~1ms) and already debounced; making `predict()` async ripples through `InlineTransactionParser` (sync API), its tests, `QuickAddTransactionIntent`, and both entry VMs. Cost exceeds gain. Revisit only if Instruments shows it on the main thread during typing.

**Verify:** unit tests pass; add parity assertions in `TodayViewModelTests` (cached totals == from-scratch recompute on fixtures). Manual: rapid month swipes, balance toggle, search typing with large sample data.

## Phase 4 — Shared dashboard scaffold (kills V1/V2 duplication)

**New `Anka/Views/Today/Shared/DashboardScaffold.swift`** — verbatim moves, NOT rewrites (modifier order encodes iOS 26 workarounds):

1. `DashboardChromeModifier` (`.dashboardChrome(vm:allTransactions:allCategories:namespace:)`): everything identical between `TodayView.swift:40-84` and `MainPageV2View.swift:26-43` — `.todaySheets`, `.task(id: vm.dashboardKey)`, sensoryFeedback set, `.onChange` feeds, `.onReceive(.ankaDataDidChange)` refetch, `.inlineComposer`, `.autoBackup`, WidgetDataWriter calls, common toolbar block (Settings top-trailing; Stats/Filter/search/Add bottom bar), `.toolbarVisibility`, `.searchable` + search behaviors, nav bar config, background, keyboard ignore. V2's extra toolbar items stay in MainPageV2View as additional `.toolbar {}` (SwiftUI merges; if iOS 26 misbehaves, fall back to `@ToolbarContentBuilder` param). Deliberate side effect: V2 gains widget updates, auto-backup, haptics it lacked.
2. `monthSwipeGesture(vm:isSwitching:)` — func returning the byte-identical DragGesture (`TodayView.swift:217-235` / `MainPageV2View.swift:137-154`).
3. `DashboardTransactionList` — skeleton/empty/grouped list (identical at `TodayView.swift:160-205` / `MainPageV2View.swift:328-370`), `horizontalPadding` param for V2.

TodayView shrinks to ~150 lines (header + scroll), MainPageV2View to ~200 (hero + chart + extra toolbar).

**Verify:** manual pass on BOTH dashboards: month swipe, tap-vs-swipe suppression, search minimize, composer open/close + bottom-bar restore, add/edit/delete/filter sheets, widget update after add, import-triggered refetch.

## Phase 5 — Unified edit flow

- `Views/Today/Shared/TodaySheets.swift:53-64` — delete `layoutRaw` branch; always `EditTransactionSheet(transaction: tx)`. Remove unused layout `@AppStorage` read.
- `EditTransactionSheet.swift` — add tag editing (VM already has full API: `tagInput`, `selectedTags`, `commitTagInput`, `removeTag`, `tagSuggestion`). One more glass row: removable `dsChip` tags + capsule TextField with suggestion. Detent 320 → 400. Fix stale header comment.
- `AddTransactionView.swift` — delete `existingTransaction` init + all edit-mode branches (delete button, "Save changes", `loadExisting`). Grep callers first (AppIntents may reference).
- `TransactionRow` — keep context-menu Edit/Delete; delete now also reachable via edit sheet trash on any row tap (closes discoverability gap; custom swipe skipped — would fight month-swipe gesture).
- Stats-sheet vs Highlights-push: keep as-is (both deliberate per DESIGN.md); one-line intent comment.

**Verify:** edit with tags from both dashboards (visible/removable/addable/persist); delete via sheet; add flow unaffected; run UI tests if runnable.

## Phase 6 — AddTransactionView decomposition + animation consolidation

**Split monolith:**
- `Components/Effects.swift` — `ShakeEffect`, `SlotCharEffect`, `SparkleCategoryLabel` (:11-73).
- `Views/AddTransaction/MorphingBottomBar.swift` — `morphingBottomBar` + `tagInputPill` (:559-731) + `sparkleButton` (:461-527).
- AddTransactionView lands ~300 lines after Phase 5 deletions.

**Animation tokens:**
- ~20 raw spring literals (lines 189,229,289,357,385,402,416,458,475,501,524-526,608,630,653,740 + `EditTransactionSheet.swift:132`) collapse to: new `DSAnimation.dsMorph` (dominant category-morph spring) + existing `dsSpring`/`dsSnappyFast`.
- sparkleButton: replace 3 stacked implicit `.animation` (:524-526) + inner (:501) with ONE `.animation(.dsMorph, value:)` on container; zero-width collapse hacks (:574-580) → `.transition(.scale.combined(with:.opacity))`. Verify feel against pre-phase video capture.
- Chart curves unified: `MainPageV2LineChart.swift:90` and `DonutChartView.swift:104,112` → `.dsEaseSlow` (matches :123).
- Update stale `DSAnimation.swift` header.
- `DateRangePicker`: tokenize 40pt/width÷4 where trivial; keep custom picker (native has no range picker).

**Verify:** build; full Add flow in simulator — category morph, sparkle, tag pill, shake — vs pre-phase capture.

## Phase 7 — Fresh visual pass (riskiest, last)

Unifying rhythm: **[context row] → [hero number] → [content]**, hero collapses on scroll.

**7a. MainPageV2 hero collapse:** replace `HeroOffsetKey` PreferenceKey hack (:97-136,385-392) with `.onScrollGeometryChange(for: Bool.self)`. Morph: NOT matchedGeometryEffect across toolbar boundary (unreliable — toolbar is separate UIKit hierarchy). Instead: hero `.scaleEffect(collapsed ? 0.4 : 1, anchor: .top)` + fade, toolbar bubble `.transition(.offset(y:8) + .opacity)`, single `.dsSnappy`.

**7b. TodayView collapsing hero via scaffold:** scaffold exposes `@Binding isScrolled`; sticky header compacts (hero font `dsHeroAmount` → `dsTitle2Bold`, Highlights link fades, period row stays), one `.animation(.dsSnappy, value: isScrolled)`. Additive — drop if it fights gradient mask/search presentation.

**7c. StatsView header:** month label → chip style matching dashboard rhythm; spacing normalized to DSSpacing; donut layout unchanged.

**7d. Highlights cards:** adopt `Card`; hero stat per DESIGN.md Title tier; verify One-Coral-Rule per card.

**Verify:** scroll video capture both dashboards (120Hz smoothness); Dynamic Type XXL; light mode.

## Phase 8 — Tests (parallel-safe with 6–7)

Swift Testing style per `AnkaTests/TodayViewModelTests.swift` (in-memory container, `@Test`/`#expect`).

- **`AppLockManagerTests.swift`** — make private crypto/lockout statics internal (`makeCredential`, `verify`, `hashPIN`, `lockoutDelay` ~:245-285); test PIN round-trip, salt uniqueness, delimiter handling, escalating lockout table. One Keychain round-trip test via test key.
- **`HighlightInsightEngineTests.swift`** — in-memory container + seeded fixtures; assert daily/weekly/monthly/topCategory math incl. zero-data and single-day edges.
- **`AutoBackupServiceTests.swift`** — extract pruning to internal `static prune(directory:keep:)`; temp dir with 10 fake backups → 7 newest survive; throttle guard as pure date comparison.

## Riskiest changes + mitigation

1. **Phase 4 scaffold** — modifier stack encodes iOS 26 workarounds. Verbatim moves, single revertible commit, manual checklist both dashboards, test toolbar merging first.
2. **Phase 3a caching** — stale cache = wrong money number. Caches written only in `refreshDashboard`; `dashboardKey` covers all inputs; parity unit tests; manual currency-switch check.
3. **Phase 7 scroll-linked morphs** — jank territory. Last phase, additive-only, V1 collapse droppable, no matchedGeometry across toolbar.

## Out of scope (tracked elsewhere)

AUDIT.md Batch 14 launch blockers (app icon, StoreKit, localization), real FX provider (ponytail stub stands), Swift 6 language mode, iPad.
