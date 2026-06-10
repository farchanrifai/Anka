# Anka Code Audit Report

_Audit date: 2026-06-10 · Reviewer: Claude Code · Scope: full `Anka/` target (Phases 0–8)_

## Executive Summary

- **Total Swift files reviewed:** 50 (~7,645 LOC)
- **Critical issues:** 3 (broken swipe-to-delete, `try!` crash-on-launch, non-`@MainActor` VM)
- **Performance improvements available:** ~6 (mostly minor; the heavy aggregation path is already well-architected)
- **Search/Filter:** **Already substantially implemented** — the prompt's premise ("Anka doesn't have search/filter yet") is out of date. Today has search + category multi-select + period/custom-range filtering. Remaining gaps are in Stats.

**Overall health: good.** The data-flow architecture (`@Query` → `update()` → `.task(id:)` → `Task.detached` with `Sendable` snapshots) is correctly implemented in Today and Stats and is the hardest part to get right. The issues below are mostly localized bugs and consistency debt, not structural problems.

---

## 1. Performance Issues

### High Priority (causes noticeable lag)
None found. The two data-heavy screens (Today, Stats) correctly offload aggregation to `Task.detached` with value-type snapshots and merge back on the main actor with cancellation checks. No N+1 query patterns, no blocking main-thread work.

### Medium Priority (may cause lag / waste)
- **`AppLockManager.biometricType` / `canUseBiometrics` allocate a fresh `LAContext()` on every access.**
  - File: `Anka/Services/AppLockManager.swift:27`, `:33`
  - These are read inside `SettingsView` body (`lockToggleLabel`, `lockToggleIcon`, footer) and re-evaluate on every render. `LAContext()` + `canEvaluatePolicy` is not free.
  - Fix: cache a single `LAContext` and compute `biometryType` once (or lazily), refreshing only when needed.

- **`TodayViewModel.displayedGroupedByDay` recomputes on every body evaluation while searching.**
  - File: `Anka/Views/Today/TodayViewModel.swift:140`
  - It's a computed property (not cached) that re-filters all day-groups on each keystroke *and* each unrelated re-render. Cheap for small datasets, but it lowercases every note/category and builds `String(Int(tx.amount))` per row each pass.
  - Fix: acceptable as-is for MVP volumes; if lists grow, debounce `searchQuery` or cache the filtered result keyed on `(searchQuery, dataVersion)`.

### Low Priority (optimization only)
- **`DonutChartView.haptic` generator is never `.prepare()`d** (`Components/DonutChartView.swift:28`) — first haptic may lag slightly. Call `prepare()` on appear. (Negligible; ported verbatim from Spendy — leave unless touching the file.)
- **`dayHeader(for:)` reduces over `group.transactions` twice in `.total` mode** (`TodayView.swift:429`) — trivial, per-section.

---

## 2. Search & Filter (status + gaps)

**Current state — already built (contradicts the prompt's assumption):**

| Capability | Today | Stats |
|---|---|---|
| Text search (note / category name / amount substring) | ✅ `.searchable` → `displayedGroupedByDay` | ❌ |
| Category filter | ✅ multi-select `CategoryFilterSheet` (Mail-style) | ❌ |
| Date-range filter | ✅ period pills (This Month / Last Month / Last 3 / This Year) + custom `DateRangePicker` | ⚠️ month-by-month nav only |
| Balance-mode filter (Expense/Income/Total) | ✅ pill switcher + swipe | ❌ (expense-only donut) |

**Remaining gaps / recommendations:**
1. **Stats has no category filter or toggle.** Add tap-to-isolate (the donut already supports tap-select internally) or expand/collapse category toggles to drive the chart.
2. **Stats has no month-comparison.** A side-by-side or overlay of two months would be high-value and matches the prompt's ask.
3. **Search is note/category/amount only** — does not cover `tags` or `paymentMethod`, which the data model supports. Add them to the `displayedGroupedByDay` predicate.
4. **Amount search is substring, not range.** `String(Int(tx.amount)).contains(q)` matches "5" inside "1500". Consider an explicit `>N` / range syntax if users find it noisy. Low priority.

**Effort:** Low-Medium (the filtering infrastructure already exists). **User value:** Medium-High for Stats filtering.

---

## 3. UI/UX Consistency Issues

### Design Token Violations (systemic — the biggest consistency debt)
The design-system tokens exist but are **under-used**; raw literals dominate the view layer.

- **Hardcoded font sizes — 33 occurrences of `.font(.system(size:))`** outside `DSFont.swift`. DSFont tokens are used 73× but raw sizes persist for *text*, not just SF Symbols:
  - `TodayView.swift:276` hero amount `.system(size: 52, weight: .black)` — there's a `dsHero` (57) / could add a token.
  - `TodayView.swift:560` row emoji `.system(size: 24)`, `:473` empty-state icon `.system(size: 48)`.
  - `DonutChartView.swift:78/85/94/101` (13/23/12) — **intentionally preserved per CONTEXT** ("preserve raw font sizes — these define the chart's feel"). Leave as-is.
  - SF Symbol sizing (`AppLockView`, `PINSetupSheet`, toolbar glyphs) is defensible, but body/label text should move to DSFont.
- **Hardcoded spacing — raw `.padding(.horizontal, 20)` etc. dominate; `DSSpacing` used only 29×.**
  - Critically, **`20` (the app's standard screen-edge inset) is not in the `DSSpacing` scale at all** (scale is 4/8/12/16/24/32/48). Every screen hand-codes `20`. Add `DSSpacing.screenEdge = 20` (or standardize to `xl`/`lg`) and apply consistently.
- **Hardcoded radii — `RoundedRectangle(cornerRadius: 14/16/12/27)` and literal `999`; `DSRadius` used only 9×.** `DSRadius.full = 999` exists but `Capsule()`/literal `999` are used directly. Map 14→`.medium`, 16→(no token; add), 12→(between small/medium).
- **Inline hex** in `AppearanceSettingsView.swift:110-111` (`"000000"`/`"1A1A1A"`) duplicates `AppearanceManager.DarkVariant` values — derive from the enum instead of re-hardcoding. (Other `Color(hex:)` calls read `category.colorHex` from the model — legitimate.)

### Accessibility
- **Good:** toolbar buttons, Add/Filter/Settings/Stats, delete, and tag controls all have `accessibilityLabel`s. Dynamic Type is handled thoughtfully in `DSFont` via `UIFontMetrics` — but only for tokens; the 33 hardcoded `.system(size:)` text usages **do not scale with Dynamic Type**.
- **Hero amount** (`.system(size: 52)`) and **day totals** won't scale for low-vision users — convert to a metric-relative token.
- Color contrast: coral `#F26666` on dark `#0E0E0E` and the `.secondary`/`.tertiary` usages are within range; no issues spotted.

### Empty States
- **Today:** ✅ excellent — distinguishes "no transactions" (with Add CTA) vs "no matches" (with Clear Filters CTA). `TodayView.swift:470`.
- **Stats:** ✅ present with guidance. `StatsView.swift:116`.
- **Loading:** ✅ Today has a skeleton row (`isLoading`). Stats sets `isLoading` but the view never renders a spinner/skeleton for it — minor; aggregation is fast.

### Error Handling
- `AddTransactionView` surfaces save/delete failures via an alert (`saveErrorMessage`) — good.
- `TodayViewModel.confirmDelete` uses `try? context.save()` — **silently swallows** save failures (`:343`). Consider surfacing.
- ML training failure only `print`s (`CategoryPredictor.swift:114`) — acceptable (background, non-user-facing).

---

## 4. Logic & State Management Issues

### 🔴 Critical
1. **Swipe-to-delete on the Today list is a no-op (dead feature).**
   - File: `Anka/Views/Today/TodayView.swift:597`
   - `.swipeActions` is a **`List`-only** modifier. Today renders rows in a `ScrollView { LazyVStack { … } }` (`:212`), so the swipe-to-delete never activates. Users can only delete via tap → edit sheet → trash.
   - Fix options: (a) move the transaction list into a `List` with `.listStyle(.plain)` + custom backgrounds, or (b) implement a custom drag gesture / add a `.contextMenu` delete. Given the bespoke pinned-header + zoom-transition design, a custom swipe or context menu is likely cleaner than converting to `List`.

2. **`try!` on `ModelContainer` creation crashes the app on launch failure.**
   - File: `Anka/AnkaApp.swift:24`
   - If the on-disk store fails to open (corruption, migration error, disk full), the app hard-crashes with no recovery path. This is the one `try!` that matters (the `SampleData.swift:63` one is previews/tests-only and fine).
   - Fix: `do/catch`, and on failure either present a recovery UI or rebuild the store (with user consent) rather than `fatalError`.

3. **`AddTransactionViewModel` is not `@MainActor`** — violates the CONTEXT rule "All ViewModels are `@Observable` and `@MainActor`."
   - File: `Anka/Views/AddTransaction/AddTransactionViewModel.swift:9-10` (`@Observable` only).
   - It mutates UI-bound state and touches `ModelContext` from `save`/`commitTag`. `TodayViewModel`, `StatsViewModel`, and `SettingsViewModel` all correctly carry `@MainActor`. Add `@MainActor` here for consistency and isolation safety.

### Data Flow / Consistency
- **`Transaction.currencyCode` defaults to `"USD"`** (`Models/Transaction.swift:25`) while the app is IDR-only and `AddTransactionViewModel.save` hardcodes `"IDR"` (`:170`). Inconsistent — and there's already a single source of truth `AppCurrency.code = "IDR"` (`NumberFormatter+Amount.swift`). Use `AppCurrency.code` in the model default and in `save()`.
- **ML negative-correction logging fires on every text-shrinking keystroke.** `handleDescriptionChange` (`AddTransactionView.swift:334`) logs a correction whenever `predictor.latestPrediction?.shouldShowChip` and text changes — this can over-weight negative signals during normal typing/backspacing. Review whether this should only log on explicit deselect.
- Add/edit/delete → UI updates correctly via `@Query` + `onChange(of: allTransactions)` re-feeding the VM and widget writer. Good.
- No race conditions observed; SwiftData `context.save()` is used (not relying on autosave) on the write paths.

### Navigation & Sheets
- Sheet dismiss/reset logic is sound; `editingTransaction`/`pendingDeleteTransaction` use computed `Binding`s that nil out on dismiss.
- **`DispatchQueue.main.asyncAfter` is used for animation sequencing** in `AddTransactionView` (shake, `closeDatePicker`, tag focus, deferred delete) and `AppLockView`. Fragile hardcoded-delay timing; works but is brittle. Consider `Task`/`await` with `Task.sleep` or animation completion. Low priority.

### Type Safety
- **Force unwraps:** `PeriodFilter.dateInterval` (`TodayViewModel.swift:24,26,29`) force-unwraps `Calendar.date(byAdding:)` results — practically safe (Gregorian arithmetic) but could `guard`. `filterLabel!` (`TodayView.swift:193`) is guarded by the `== nil` ternary — safe but reads awkwardly; bind with `if let`. `tx.note!` (`:568`) is guarded by `tx.note?.isEmpty == false` — safe.
- Enums used well (`TransactionType`, `BalanceMode`, `PeriodFilter`, appearance modes) — no stringly-typed state in the hot paths. ✅
- PIN is stored in Keychain as **plaintext** and compared directly (`AppLockManager.verifyPIN`). Keychain encrypts at rest so this is acceptable for MVP, but hashing the PIN would be a defense-in-depth improvement. Low priority.

---

## 5. Code Organization & Reusability

- **Missing reusable components named in CONTEXT.** The folder spec lists `Components/TransactionRow.swift`, `AmountLabel.swift`, `SectionHeader.swift` — **none exist.** `Components/ComponentsPlaceholder.swift` is still a stub. The transaction row (~55 lines) is inlined in `TodayView.transactionRow`, and Stats has a parallel `categoryRow`. Extract a `TransactionRow` and an `AmountLabel` (the `"Rp \(amount.idrShort)"` capsule pattern is repeated 3×).
- **Duplicated `Sendable` snapshot structs.** `TxSnap` (`TodayViewModel.swift:381`) and `StatsTxSnap` (`StatsViewModel.swift:8`) are identical. Share one internal type.
- **Duplicated VM scaffolding.** Today and Stats repeat the `dataVersion` + `update()` + `refreshKey`/`dashboardKey` + `Task.detached` pattern. A small `AggregatingViewModel` protocol/base could DRY this, though duplication is mild.
- **Stray scratch files at repo root:** `test2.swift`, `test3.swift` (untracked) are toolbar-search experiments — not in the target, not in `Anka/`. Delete them.
- **Dead field:** `SettingsViewModel.darkModeEnabled` (`:9`) — CONTEXT explicitly notes it's superseded by `AppearanceManager` and "can be removed when convenient." Remove.

---

## 6. Recommendations by Priority

### Phase 0 — Do immediately (fixes correctness bugs)
- [ ] Fix swipe-to-delete on Today (`TodayView.swift:597`) — it currently does nothing in a `ScrollView`/`LazyVStack`.
- [ ] Replace `try! ModelContainer(...)` in `AnkaApp.swift:24` with graceful failure handling.
- [ ] Add `@MainActor` to `AddTransactionViewModel`.

### Phase 1 — Do soon (consistency + small perf)
- [ ] Centralize currency on `AppCurrency.code` (fix `Transaction` default `"USD"` + hardcoded `"IDR"` in `save`).
- [ ] Cache `LAContext` in `AppLockManager` instead of allocating per access.
- [ ] Remove dead `SettingsViewModel.darkModeEnabled`; delete `test2.swift` / `test3.swift`.
- [ ] Review ML negative-correction logging cadence in `handleDescriptionChange`.

### Phase 2 — Nice to have (UX + design tokens)
- [ ] Add `DSSpacing.screenEdge` (=20) and migrate the pervasive raw `.padding(.horizontal, 20)`.
- [ ] Move text `.font(.system(size:))` usages to `DSFont` tokens (Dynamic Type support) — exclude DonutChart per CONTEXT and SF-Symbol sizing.
- [ ] Add Stats category filter/toggle + month comparison.
- [ ] Extend Today search to `tags` / `paymentMethod`.
- [ ] Extract `TransactionRow` / `AmountLabel` components.

### Phase 3 — Future (polish / hardening)
- [ ] Replace `DispatchQueue.main.asyncAfter` animation sequencing with structured concurrency.
- [ ] Hash the stored PIN.
- [ ] Surface `confirmDelete` save errors instead of `try?`.
- [ ] Share the `Sendable` snapshot struct and factor common VM scaffolding.

---

## 7. File-by-File Summary

```
AnkaApp.swift               ⚠️  try! ModelContainer = crash-on-launch risk; migration logic otherwise clean
App/AppRouter.swift         ✅  Minimal, correct osScheme mirroring
DesignSystem/DSColor        ✅  Clear static fallbacks; variant logic correctly lives on AppearanceManager
DesignSystem/DSFont         ✅  Excellent Dynamic-Type-aware tokens — but under-adopted by views
DesignSystem/DSSpacing      ⚠️  Scale missing the most-used value (20); views bypass it
DesignSystem/DSRadius       ⚠️  Fine, but views hardcode radii instead of using it
DesignSystem/Color+Hex,DateHelpers,NumberFormatter  ✅  Clean utilities; AppCurrency.code is the currency SoT
Models/Transaction          ⚠️  Default currencyCode "USD" inconsistent with IDR-only app
Models/Category             ✅  Clean; cascade inverse relationship correct
Models/TransactionType,SampleData  ✅  Fine (SampleData try! is test-only)
Views/Today/TodayView       🔴  swipeActions no-op (not in a List); pervasive raw font/padding/radius; strong empty/skeleton states
Views/Today/TodayViewModel  ✅  Exemplary async aggregation; minor force-unwraps in PeriodFilter
Views/Today/CategoryFilterSheet  ✅  Solid multi-select filter (search/filter already exists!)
Views/Stats/StatsView       ✅  Clean; no loading indicator; no category filter
Views/Stats/StatsViewModel  ✅  Correct @MainActor async pattern; snapshot struct dup'd with Today
Views/AddTransaction/View   ⚠️  Rich UX; many hardcoded sizes; asyncAfter timing; ML over-logging
Views/AddTransaction/VM     🔴  Missing @MainActor; hardcodes "IDR"
Views/AddTransaction/CategoryPickerView  ✅  Good DSToken adoption (model to copy)
Views/Settings/SettingsView ✅  Thorough; well-documented appearance/scheme handling
Views/Settings/SettingsViewModel  ⚠️  Dead darkModeEnabled field
Views/Settings/* (Backup/Data/Import/Export/Category)  ✅  Functional; some hardcoded sizes
Views/AppLock/*             ✅  Sound lock gating; hardcoded font sizes; PIN stored plaintext (low risk)
Components/DonutChartView   ✅  Ported verbatim; raw sizes intentional per CONTEXT
Components/ComponentsPlaceholder  ⚠️  Still a stub; promised TransactionRow/AmountLabel/SectionHeader never built
Components/DateRangePicker,AutoFocusTextField  ✅  Purpose-built, reasonable
Services/CategoryPredictor  ✅  Clean 3-layer pipeline; @MainActor @Observable; background training off-main
Services/AppLockManager     ⚠️  LAContext allocated per access; otherwise correct
Services/AppearanceManager  ✅  Well-reasoned; the dark-variant/scheme handling is the trickiest part and it's right
Services/* (CSV/Backup/Keychain/Widget/Keyword/MLTrainer)  ✅  Not deeply audited; no obvious issues
test2.swift / test3.swift   ❌  Scratch experiments at repo root — delete
```

---

### Appendix — Critical fixes (problem → fix)

**A. Swipe-to-delete (TodayView.swift:597)**
```swift
// PROBLEM: .swipeActions only works inside a List. Today uses
// ScrollView { LazyVStack { ... } }, so this is dead code.
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button { vm.requestDelete(tx) } label: { Label("Delete", systemImage: "trash") }.tint(.red)
}

// FIX (option A, least invasive): add a context menu that DOES work outside List
.contextMenu {
    Button(role: .destructive) { vm.requestDelete(tx) } label: { Label("Delete", systemImage: "trash") }
}
// FIX (option B): host the day-grouped rows in a `List` with .listStyle(.plain)
//   + .listRowBackground/.listRowInsets to preserve the current look, keeping
//   .swipeActions functional.
```

**B. Crash-on-launch (AnkaApp.swift:24)**
```swift
// PROBLEM
let container = try! ModelContainer(for: Transaction.self, Category.self, configurations: config)

// FIX
let container: ModelContainer
do {
    container = try ModelContainer(for: Transaction.self, Category.self, configurations: config)
} catch {
    // log, then either present a recovery screen or rebuild the store with consent
    fatalError("ModelContainer init failed: \(error)") // at minimum, attach context
}
```

**C. ViewModel actor isolation (AddTransactionViewModel.swift:9)**
```swift
// PROBLEM
@Observable
final class AddTransactionViewModel { ... }

// FIX (matches TodayViewModel / StatsViewModel / SettingsViewModel)
@MainActor
@Observable
final class AddTransactionViewModel { ... }
```
