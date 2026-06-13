# Anka — Claude Code Project Context

> Read this file at the start of every Claude Code session before doing anything.
> Update the Phase Status section after each completed phase.

---

## App Identity

- **Name:** Anka
- **Platform:** iOS only (no macOS, no Android)
- **Minimum iOS:** 26.0 (uses Liquid Glass tab bar APIs: `role: .search` detached Add button, `.tabBarMinimizeBehavior`)
- **Bundle ID:** nc.Anka (widget extension: nc.Anka.AnkaWidgets)
- **App Group:** group.com.nc.Anka
- **Purpose:** Personal expense tracker — manual-entry first, fast logging, beautiful design
- **Target user:** Global audience, single user, no collaboration
- **Model:** Subscription (StoreKit 2), 14-day free trial, annual-first
- **Philosophy:** Low friction logging + beautiful opinionated design. "It just works."

---

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift |
| UI | SwiftUI |
| Database | SwiftData (local only until Phase 10) |
| Architecture | @Observable ViewModels |
| Charts | Swift Charts |
| ML | Create ML + NaturalLanguage (on-device) |
| Security | LocalAuthentication + Keychain |
| Sync | iCloud/CloudKit (Phase 10 only — not now) |
| Subscription | StoreKit 2 (no RevenueCat) |
| Testing | Swift Testing + XCTest UI Tests |

---

## Architecture Rules

- Views own `@Query` and push data into ViewModels via `update()` methods
- Heavy computation runs in `Task.detached` with Sendable snapshots
- `.task(id:)` triggers recomputes, never `onAppear` for data loading
- All ViewModels are `@Observable` and `@MainActor` _(✅ all VMs now conform, incl. `AddTransactionViewModel`)_
- No Firestore. No Firebase. No backend. Ever.
- No authentication required to use the app
- No multi-profile system
- Local SwiftData is the only persistence until Phase 10

---

## Design System

All views must use these tokens only. Never hardcode values.

### Colors (DSColor.swift)
- **Accent:** `#F26666` (coral)
- **Background primary:** `#0E0E0E` (dark)
- **Card surface:** `#1A1A1A`
- **Secondary surface:** `#222222`
- Adaptive light/dark via DSColor tokens

### Fonts (DSFont.swift) — ported from Spendy
- dsHero, dsTitle, dsHeadline, dsSubhead, dsBody, dsCaption, dsBadge (+ weight/size variants), plus `dsHeroAmount` (52/.black, Today hero) and `dsEmoji` (24, row emoji)
- No custom fonts at MVP. Tokens declared with a `relativeTo:` text style are **UIFontMetrics-scaled** (Dynamic Type); the bare `Font.system(size:)` ones are fixed-size — prefer the scaled variants for new text.

### Radius (DSRadius.swift)
- `dsSmall` = 8
- `dsMedium` = 14
- `dsLarge` = 20

### Spacing (DSSpacing.swift)
- Scale: 4, 8, 12, 16, 24, 32, 48 · plus `screenEdge` = 20 (standard horizontal screen inset)

---

## Data Models

### Transaction @Model
```swift
id: UUID
amount: Double
type: TransactionType // .expense / .income
date: Date
createdAt: Date
note: String?
category: Category?
currencyCode: String // defaults to AppCurrency.code ("IDR") — single source of truth in NumberFormatter+Amount.swift
tags: [String] // optional, freeform
paymentMethod: String? // optional, e.g. "Cash", "Visa"
```

### Category @Model
```swift
id: UUID
name: String
emoji: String
colorHex: String
type: TransactionType
sortOrder: Int
transactions: [Transaction] // @Relationship(deleteRule: .cascade, inverse: \Transaction.category)
```

### TransactionType enum
`String`-backed, `Codable, CaseIterable, Hashable`: `.expense` / `.income`, each with a `displayName`.

### Seeding & Sample Data (`Models/SampleData.swift`)
- `createDefaultCategories()` → 12 defaults (6 expense, 6 income), each with emoji + hex color + `sortOrder`.
- `container()` → in-memory `ModelContainer` for previews/tests, pre-seeded with the 12 categories + 3 sample transactions.
- `AnkaApp.init()` builds the on-disk `ModelContainer(for: Transaction.self, Category.self)` and seeds the 12 default categories only when the store is empty (first launch).

---

## App Navigation

**Liquid Glass tab bar (iOS 26):**
- Left pill/island: **Today** only — the Reports tab was removed; **Stats** is reached via the `chart.pie` button in Today's top-bar trailing toolbar group (`StatsToolbarButton`), presented as a **sheet** that zooms out of the icon (`matchedTransitionSource(id: "stats")` + `.navigationTransition(.zoom)`). It inherits Today's selected month one-way (`initialMonth`).
- Right detached button: **Add** — `role: .search` detaches it from the pill; intercepted via `onChange` (opens sheet, restores previous tab, does NOT navigate)
- `.tabBarMinimizeBehavior(.onScrollDown)` — bar minimizes as content scrolls down

**Settings:** floating gear icon (top-right) on **Today** → presents `SettingsView` as a sheet (modal, not a tab). Native `List` with sections (current state):
- **General** — Categories (→ `CategoryManagementView`, with a count badge) · Default Currency (read-only "IDR")
- **Appearance** — Theme (→ `AppearanceSettingsView`; badge shows mode · dark-variant). _Note: the old inline "Dark Mode toggle" described in earlier specs is gone — it's now a navigation row._
- **Security** — App Lock toggle (Face ID/Touch ID/Optic ID/PIN) · Change PIN · Remove PIN (see App Lock section)
- **Data** — Backup & Restore (→ `BackupSettingsView`) · Import & Export (→ `DataManagementView`). _Both are fully built — no longer the "Export stub" described in earlier specs._
- **About** — Version

`CategoryManagementView` is the sub-menu: native List split into Expense / Income sections, swipe-to-delete via `.onDelete`, drag-to-reorder via `.onMove` + `EditButton`, `+` toolbar button presents `AddEditCategorySheet` for add/edit/delete.

**Add Transaction flow (Spendy-adapted layout):** full-screen modal, top→bottom:
- Top bar: `Cancel` capsule (left) · `•••` options-placeholder capsule (right, inert — recurring lives in a later phase)
- Centered amount: `IDR` prefix + whole-number value with thousands separator (e.g. `IDR 12,345`), animated `.numericText()` transition
- Centered `Add note` text field (focuses the system keyboard; numpad fades out while editing)
- Flexible spacers push the action row + numpad to the bottom
- Category + Date + Save row (all 48 pt tall): compact category slot (opens picker **sheet** — segmented Expenses/Income tabs + scrollable list, `.medium`→`.large` detents) · functional date pill (`DD`/`MON`, tap = inline `DatePicker`) · coral Save capsule (disabled until amount + category set)
- Numpad: 1–9, then note-key (✎) · 0 · `⌫`. No per-key backgrounds; each key is a full-cell tap target and the grid expands to fill available height. IDR amounts are whole numbers, so the note key replaces the decimal.

**Current state (updated):** the entry flow is now backed by `AddTransactionViewModel` (`Views/AddTransaction/AddTransactionViewModel.swift`) and **persists to SwiftData** (Phase 2/3 done — the earlier "no ViewModel / Save just dismisses" note is obsolete). The same view handles **edit** (`existingTransaction`) and **delete** of an existing transaction. It also adds:
- **Tags** — a morphing bottom bar with a tag-input pill (shadow-suggestion autocomplete drawn from prior transactions' tags). Tags are plain `[String]` on `Transaction`.
- **ML auto-categorization** — debounced prediction on the description field (see ML section).
- ✅ `AddTransactionViewModel` is now `@MainActor @Observable` (deviation fixed).

**Currency:** the app is IDR-only at present. `NumberFormatter+Amount.swift` defines `AppCurrency.code = "IDR"` as the single source of truth. ✅ Both the `Transaction` model `init` default and the save path now resolve to `AppCurrency.code` (the old hardcoded `"USD"` default and `"IDR"` literal are gone). Multi-currency entry (USD/EUR/etc.) + FX conversion is Phase 9 (not started).

---

## Appearance (Theme + Dark Variant)

`Services/AppearanceManager.swift` is `@MainActor @Observable`, owned by `AnkaApp` as `@State` and injected via `.environment`.

- `Mode`: `.system / .light / .dark` — persisted as `anka.appearanceMode`. Maps to SwiftUI's `.preferredColorScheme(_:)` applied at WindowGroup level.
- `DarkVariant`: `.black (#000000) / .gray (#1A1A1A)` — persisted as `anka.darkVariant`. Only meaningful in dark mode (light mode ignores it).

**Variant resolution lives on AppearanceManager, NOT on DSColor.** Earlier attempts used `UIColor(dynamicProvider:)` inside `DSColor.bgPrimary` etc — but those closures only re-evaluate on **trait** changes, not on UserDefaults writes. Forcing a trait pass either via `overrideUserInterfaceStyle` toggle or via a SwiftUI scheme-shake both caused either intermittent failures or a visible flash. Don't bring those approaches back.

Current design: `AppearanceManager` exposes `@Observable` helper methods that take the calling view's `@Environment(\.colorScheme)` and return a plain `Color`:

```swift
func bgPrimary(_ scheme: ColorScheme) -> Color
func bgCard(_ scheme: ColorScheme) -> Color
func bgGrouped(_ scheme: ColorScheme) -> Color
// + bgSecondary, bgTertiary
```

| Helper | Light | Dark · Pure Black | Dark · Soft Dark |
|---|---|---|---|
| bgPrimary | systemBackground | #000000 | #1A1A1A |
| bgCard | secondarySystemGrouped | #1A1A1A | #242424 |
| bgSecondary | secondarySystem | #1C1C1E | #2C2C2C |
| bgTertiary | tertiarySystem | #2C2C2E | #3A3A3C |
| bgGrouped | systemGrouped | #000000 | #1A1A1A |

When the user changes mode or variant, `AppearanceManager` publishes, dependent views re-render, the helper is re-called with current state, the returned `Color` is fresh. No trait shake, no flash, instant. SwiftUI's `@Environment(\.colorScheme)` reflects whatever `.preferredColorScheme` the app/sheet applies, so it's already the effective scheme for mode resolution.

**DSColor.bg* tokens still exist** as static fallbacks for contexts where `@Environment` isn't readable (widgets, lock screen overlay, simple previews). They use system colors and do **not** honor the dark variant. Refactored views use `appearance.bgX(scheme)`; legacy paths use `DSColor.bgX`.

**Native List + variant.** iOS's native `List` paints its own UIKit-managed background that bypasses our colors entirely. To make `SettingsView` / `AppearanceSettingsView` / `CategoryManagementView` follow the variant, those views apply:

```swift
.scrollContentBackground(.hidden)
.background(appearance.bgGrouped(scheme))
```

…on the `List`, and `.listRowBackground(appearance.bgCard(scheme))` on each `Section`. Without these, the List would always show `systemGroupedBackground` regardless of variant.

**Sheet propagation note.** `.preferredColorScheme(...)` at the WindowGroup level doesn't always re-propagate into sheets that are already presented (SwiftUI sheet hosts are independent `UIHostingController`s that subscribe to env at presentation time but don't always re-subscribe on parent env changes). To make mode changes update sheets immediately, **also apply `.preferredColorScheme` on the sheet roots** (currently: `SettingsView`, `AddTransactionView`). The lock screen `AppLockView` is overlaid in the same ZStack as `AppRouter` so it shares the WindowGroup-level modifier directly.

**`.system` → sheet quirk.** Two SwiftUI gotchas around sheet roots and `.preferredColorScheme`:

1. Passing `nil` to `.preferredColorScheme` on a sheet does NOT release a previously-applied explicit override. Once a sheet has been given `.light`/`.dark`, `nil` won't un-stick it — you'd need to close and reopen the sheet.
2. Conditionally omitting the modifier via `@ViewBuilder` changes the view's structural type, which causes SwiftUI to **tear down the NavigationStack inside** — popping the user from `AppearanceSettingsView` back to the main `SettingsView` on every mode toggle.

**Fix:** apply `.preferredColorScheme(appearance.effectiveScheme)` unconditionally on sheet roots. `effectiveScheme` is never nil — it's `.light`/`.dark` for explicit modes, and **the live OS scheme** for `.system`. Always concrete + always applied = stable view structure (no nav pop) and clean trait transitions (no stuck overrides).

The OS scheme is tracked in `AppearanceManager.osScheme`, mirrored from `AppRouter`'s `@Environment(\.colorScheme)` via `.onChange`. `AppRouter` sits inside the WindowGroup's `.preferredColorScheme(mode.preferredColorScheme)` — so when mode is `.system` (modifier resolves to nil), the WindowGroup follows the OS and AppRouter's env scheme IS the OS scheme. For `.light`/`.dark` modes the env reflects our override, which is also written to `osScheme` but unused (`effectiveScheme` short-circuits before reading it).

Settings flow: **Settings → Appearance** (NavigationLink pushes `AppearanceSettingsView`). Sub-page has two sections — Theme (System/Light/Dark) and Dark Variant (Pure Black/Soft Dark). The Dark Variant section is `.disabled` (still visible) when mode is Light, so toggling modes doesn't shift the layout.

The old `darkModeEnabled` toggle in `SettingsViewModel` (a leftover from Phase 5) was non-functional and superseded by the AppearanceManager — ✅ the dead field has now been removed from the VM.

## Today View — Search behavior gotcha

`TodayView` uses iOS-26's bottom-toolbar search pattern: `.searchable(text:)` + `DefaultToolbarItem(kind: .search, placement: .bottomBar)` + `.searchToolbarBehavior(...)`. By default, activating the search field triggers `UISearchController`'s **search-presentation mode**, which slides the underlying content up out of view (it assumes the search results will replace the original content). This caused the sticky header (Expense/Income/Total + amount + Stats) to disappear when the keyboard came up.

**Fix:** `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the `.searchable` chain. iOS 18.2+ modifier that keeps the underlying content in place while search is active. This is **not** a keyboard-avoidance issue — `.ignoresSafeArea(.keyboard)` and `.scrollDismissesKeyboard(.never)` do not help, since the shift comes from `UISearchController` not from the keyboard inset itself.

Cosmetic UIKit warnings persist (`SearchBarHidesWhenScrolling-default` vs `-explicit`, `Adding UIKitToolbar as subview...`, constraint conflicts on `_UIButtonBarButton`) — these are known SwiftUI↔UIKit bridge noise from the bottom-toolbar search pattern in iOS 26 and don't affect runtime behavior.

## Search & Filter (Today) — IMPLEMENTED

> Earlier specs treated search/filter as a future gap. **It is built.** Today's bottom toolbar is the iOS Mail pattern: **Filter • Search • Add**.

- **Text search** — `.searchable(text: $vm.searchQuery)`. Filtering happens in the **view layer** via `TodayViewModel.displayedGroupedByDay` (a computed pass over the already-aggregated `groupedByDay`), so each keystroke does NOT re-fire the heavy `refreshDashboard()` pipeline or invalidate `dashboardKey`. Matches `note`, `category.name`, and an amount **substring** (`String(Int(amount)).contains`). Does **not** yet search `tags` or `paymentMethod`.
- **Category filter** — `CategoryFilterSheet` (presented from the Filter button via a Mail-style zoom transition). Multi-select, two-way bound to `TodayViewModel.selectedCategories`. The Filter button renders as a plain icon when idle and a "Filtered by …" pill when active. Category filtering runs **inside** `refreshDashboard()` (it's part of `dashboardKey`), unlike text search.
- **Period filter** — pills in the filter sheet: This Month / Last Month / Last 3 Months / This Year / **Custom**. Custom pushes `DateRangePicker` and drives `customStartDate`/`customEndDate`. `PeriodFilter.dateInterval` resolves the range (⚠️ force-unwraps Calendar math — safe in practice).
- **Balance mode** — Expense / Income / Total pill switcher in the hero (also swipeable). Drives which transactions + totals are shown.

**Remaining gaps:** Stats has **no** category filter (month-over-month comparison + an income/net summary line were added in the Stats redesign; the donut + breakdown are still expense-focused by design). Extending Today search to tags/paymentMethod is also pending. See `Anka_Code_Audit.md` §2.

**Row delete (fixed):** rows render in a `ScrollView { LazyVStack }` (not a `List`), where `.swipeActions` is a no-op. Delete + Edit now live in a **long-press `.contextMenu`** on `TransactionRow` (Edit → `onEdit`, Delete → `onDelete`); the tap-to-edit action is unchanged. A failed delete surfaces a **"Delete Failed"** alert (`TodayViewModel.deleteErrorMessage`, set from `confirmDelete`'s `do/catch`) instead of failing silently.

## Backup / Import / Export (Data section) — IMPLEMENTED

> Earlier specs listed this as an "Export stub". It is now a working feature set.

- **`BackupService`** — versioned JSON (`AnkaBackup`, `currentVersion = 1`) export/import. Restore de-duplicates by original `Transaction.id` and reports imported/skipped/updated/deleted + warnings (`BackupImportResult`). Categories are referenced by **name** in the payload.
- **`AutoBackupService`** (`@MainActor @Observable`, singleton) — maintains up to **7 rolling JSON backups** in two locations (App Group `Backups/` + app `Documents/Backups/`). `BackupSettingsView` lists/restores/deletes them and triggers `performBackup()` manually. ⚠️ The service header describes automatic triggers on every save/delete and on 24h foreground, **but those are not wired** — `performBackup()` is only ever called from the manual "Back Up Now" action. If automatic backups are intended, wire `performBackup`/`shouldBackup` into the save/delete paths and `scenePhase`.
- **`CSVService`** — CSV export (8-column: date,type,category,amount,note,tags,currency,paymentMethod) + parse-with-preview (no direct DB writes; commit happens after the user confirms in `ImportPreviewSheet` → `ImportSummarySheet`). Reached via Settings → Data → Import & Export (`DataManagementView`).

## App Lock (Phase 8)

`Services/AppLockManager.swift` is `@MainActor @Observable`, owned by `AnkaApp` as `@State` and injected via `.environment(lockManager)`. Single source of truth for:

- `appLockEnabled: Bool` — persisted to `UserDefaults` under `anka.appLockEnabled` (the `didSet` writes through automatically)
- `isLocked: Bool` — transient, flips between launches/foreground/background
- `hasPIN: Bool` — derived from `KeychainHelper.read(forKey: "ankaPINCode") != nil`
- **`biometricEnabled: Bool`** — persisted **user preference** (`anka.appLock.biometricEnabled`, default `true`) for using Face ID / Touch ID. Distinct from `canUseBiometrics` (the *hardware* capability). `useBiometrics` = `canUseBiometrics && biometricEnabled` is the effective gate the lock screen reads — so the user can keep the lock **PIN-only** even on a biometric device.
- `gracePeriod: GracePeriod` — auto-lock grace window (`anka.appLock.gracePeriod`); see grace-period note below.
- Biometric helpers: `biometricType`, `canUseBiometrics`, `authenticateWithBiometrics() async -> Bool`
- PIN: `savePIN`/`removePIN`/`verifyPIN` (PIN is a per-PIN salted SHA256 credential in the Keychain; see Batch 5 hardening). All key literals are `static let` on the manager.

`KeychainHelper` uses service `nc.Anka` (separate from the App Group ID); items are written `WhenUnlockedThisDeviceOnly`.

**Lock gate at app root** — `AnkaApp.body` wraps `AppRouter` in a `ZStack` and overlays `AppLockView` when `lockManager.isLocked` is true. `.onChange(of: scenePhase)` calls `enterBackground()` on `.inactive`/`.background` and `enterForeground()` on `.active` (these cover the UI for app-switcher privacy and honor the grace period); both bail when `appLockEnabled == false` OR `hasPIN == false` — so the user can never be stranded. ⚠️ The overlay lives in the **root ZStack**, *beneath* any presented sheet — so engaging the lock while a sheet (e.g. Settings) is open won't surface it until the sheet closes (see "Immediate prompt on activation").

**PIN is mandatory when enabling.** The Settings toggle won't flip `appLockEnabled` to true unless a PIN exists; it presents `PINSetupSheet` first. Biometric is an opt-in fast path on top of the PIN.

**Immediate prompt on activation.** Enabling App Lock (toggle-with-PIN, or finishing `PINSetupSheet`) routes through `SettingsView.engageLock()` → `appLockEnabled = true` + `lock()` + **`dismiss()` of the Settings sheet**. The dismiss is required because the lock overlay is beneath the sheet; without it the lock screen (and biometric prompt) would only appear on the next launch — the "didn't ask for Face ID right after activating" bug.

**Settings security section** lives in the existing native `List` (Settings → Section "Security"):
- Toggle: **"App Lock"** (generic `lock.fill`) — enables/disables the lock.
- Toggle: **"Use Face ID" / "Use Touch ID" / "Use Optic ID"** (only when `canUseBiometrics`) — drives `biometricEnabled` (PIN-only vs PIN + biometrics).
- "Require Unlock" — grace-period picker (`Immediately` / `30s` / `1m` / `5m`).
- "Change PIN" — re-runs `PINSetupSheet`.
- "Remove PIN" — confirmation dialog, then `removePIN()` + `appLockEnabled = false` together.

**Lock screen UX** (`AppLockView`):
- When `useBiometrics`: auto-prompts biometric once on first appearance via `.task`; if it fails/cancels, falls through to PIN. When `biometricEnabled` is off (PIN-only): the keypad is shown **directly** (no biometric button, no "Back to Face ID" link), focused on appear.
- 4-digit PIN auto-submits on the 4th character; wrong PIN clears + error haptic; escalating brute-force lockout with a live countdown.
- "Use PIN instead" / "Back to Face ID" toggles between the two methods (biometric mode only).

## ML Auto-Categorization (Phase 6)

3-layer pipeline lives in `Services/CategoryPredictor.swift`:
1. **KeywordMatcher** — static dictionary, fires first
2. **UserCategoryClassifier** — `NLModel` trained on the user's own transactions via CreateML, stored in App Group container as `UserCategoryClassifier.mlmodelc`. Threshold 0.75.
3. **StarterCategoryClassifier** — bundled `.mlmodelc` in `Resources/`, softest fallback. Threshold 0.60.

`Prediction.shouldAutoAssign` (≥0.85) silently assigns; `Prediction.shouldShowChip` (0.60–0.85) shows the sparkle pill.

**Lifecycle in AddTransactionView:**
- `CategoryPredictor` is created once in `AnkaApp` (`@State`) and injected via `.environment(predictor)`. The view reads it via `@Environment(CategoryPredictor.self)`.
- `descriptionField.onChange` calls `vm.triggerMLPrediction(note:predictor:)` — 400 ms debounce in a cancellable `Task`. On empty text, the ML-assigned category is cleared.
- **Auto-type switch.** `applyMLPrediction` first looks for a name match in `selectedType`; if none, falls back to the opposite type and updates `selectedType` along with the category. Lets the user type "gaji" / "salary" / "freelance" while still on Expense mode and have the sheet flip to Income automatically.
- `vm.sparkleActive` is computed (`!descriptionText.isEmpty`) so the sparkle icon pulses while typing.
- On manual deselect of an ML-picked category (the `sparkleButton` tap): logs negative correction (`actual: nil`). This is the **only** place a negative correction is logged — earlier code also logged one on every keystroke/backspace in `handleDescriptionChange`, which over-weighted negatives and degraded the model; that spurious logging has been removed.
- On save with a user-overridden category: logs positive correction (`actual: <picked name>`).
- After successful save: `predictor.trainIfReady(transactions: vm.trainableSnapshots())` kicks background CreateML training (gated to ≥20 transactions, +10 since last train).

Correction signals live in `UserDefaults(suiteName: PlatformPaths.appGroupID)` under key `ml_corrections`, weighted 2x during the next training pass.

**⚠️ Category-name coupling.** The bundled `StarterCategoryClassifier` and `KeywordMatcher` emit a fixed set of label strings — Anka's default categories in `SampleData.createDefaultCategories()` must match those strings exactly, or `applyMLPrediction` silently fails to look up the SwiftData `Category`. Locked taxonomy: **Home · Groceries · Eating Out · Food Delivery · Coffee · Car · Taxi · Health · Shopping · Entertainment** (expense) and **Salary · Freelance · Investment** (income, ML-relevant). `Bonus / Other Income / Refund` are Anka-only extras (no ML hits, but harmless). Do not rename any locked entry without retraining the model.

`AnkaApp.seedOrMigrateCategories()` runs a one-time wipe of the legacy pre-ML defaults (Food & Dining / Transport / Utilities / Other Income / Refund) and re-seeds, gated by `UserDefaults` key `anka.categoryMigration.v2`. Transactions are unlinked first so the `.cascade` delete doesn't drop them.

### TODO — globalize ML training data

Both `KeywordMatcher` and `StarterCategoryClassifier` were ported from Spendy and are heavily **Indonesia-skewed** (Indomaret, GoFood, Grab, Pertamina, PLN, Apotek, warteg, etc.). Anka targets a global audience (CONTEXT § App Identity), so before public launch the training data needs broadening:

- **KeywordMatcher** (`Services/KeywordMatcher.swift`) — extend dictionaries with global merchants/brands per category. Minimum coverage targets:
  - Groceries: Whole Foods, Trader Joe's, Tesco, Sainsbury's, Aldi, Lidl, Walmart, Costco, FairPrice, NTUC, Cold Storage, Don Quijote, AEON, 7-Eleven
  - Eating Out: McDonald's, Chipotle, Panera, Nando's, Pret, Wagamama, Yoshinoya, Saizeriya, Sushiro
  - Coffee: Starbucks (have), Blue Bottle, Costa, Pret, Tim Hortons, Doutor, Tully's, %Arabica
  - Food Delivery: DoorDash, Uber Eats, Deliveroo, Just Eat, foodpanda, Wolt, Rappi, Swiggy, Zomato, Meituan
  - Taxi: Uber, Lyft, Bolt, Cabify, DiDi, Ola, Comfort
  - Car: Shell (have), BP, Esso, Chevron, Mobil, Texaco, EV charging keywords (Supercharger, Ionity, Electrify America)
  - Home: Verizon, AT&T, Comcast, BT, Sky, Vodafone, EE, Singtel, electricity/water bill keywords in EN/JA/KO/ES/FR/DE
  - Health: CVS, Walgreens, Boots, Watsons, pharmacy/clinic generic terms across languages
  - Shopping: Amazon, eBay, Target, IKEA, Uniqlo, H&M, Zara, ASOS
  - Entertainment: Netflix (have), Apple TV+, Hulu, HBO, Prime Video, Crunchyroll, Steam (have), Epic Games, AMC, Cineworld

- **StarterCategoryClassifier** (`Resources/StarterCategoryClassifier.mlmodel`) — retrain with a globally-balanced corpus. Plan:
  1. Generate a synthetic + curated multi-locale dataset (EN-US, EN-UK, EN-SG, JA, KO, ES, FR, DE, ID baseline) — ≥200 labeled samples per category, mix of merchant names, generic terms, and short notes like "lunch", "coffee", "uber"
  2. Train with `MLTextClassifier` (mirroring `CategoryMLTrainer`) — locale parameter on `MLTextClassifier.ModelParameters(language: .english)` may need replacing with `.unspecified` or one model per language
  3. Drop the new `.mlmodel` into `Anka/Resources/` (replaces the existing file)
  4. Keep the same 10 expense + 3 income labels — do **not** rename, since `SampleData` defaults are coupled to them
  5. Re-test the suite: `grab food`, `doordash`, `tesco`, `7-eleven`, `uber pool`, `shell gas`, `cvs pharmacy`, `verizon bill`, `netflix`

- **Fallback strategy while ML is IDR-skewed**: keyword pass already runs Layer 1 with confidence 0.90 (auto-assign). Adding global merchant strings to `KeywordMatcher` gives an immediate quality lift without retraining. Do that first.

- **Internationalization concern**: amount buckets (`micro` < 20k / `small` < 100k / etc.) are tuned for **IDR** ranges. When supporting USD/EUR/etc., either (a) convert to a normalized "small/medium/large" tier based on the user's home currency, or (b) drop the amount bucket from the input string entirely. Decide before retraining — input format must match what the model was trained on.

---

## NLP Description Parsing (Phase 9+)

`Services/TransactionParser.swift` turns the Add-Transaction description into structured fields. Pure, stateless, non-actor (`final class … : Sendable`, `static let shared`) so it's callable anywhere and unit-testable. `parse(_:) -> ParsedTransaction(amount:currencyCode:note:confidence:)`.

**What it extracts** (examples → amount / currency / note / confidence):
- "5 dollar for grabfood" → 5 / USD / "grabfood" / 0.9
- "100 eur hotel in paris" → 100 / EUR / "hotel in paris" / 0.9
- "5k transport" → 5000 / IDR / "transport" / 0.7  (magnitude shorthand defaults to IDR)
- "2.5m rent" → 2,500,000 / IDR / "rent" / 0.7
- "1b acquisition" → 1,000,000,000 / IDR / "acquisition" / 0.7
- "5.50 coffee" → 5.5 / nil / "coffee" / 0.6  (bare number; currency left to the caller's default)
- "just coffee" → nil / nil / "just coffee" / 0

Rules: comma = thousands separator, dot = decimal (IDR locale). **Magnitude suffixes** (case-insensitive) multiply the number — English `k`/`m`/`b` and Indonesian `rb`/`ribu` (×1,000), `jt`/`juta` (×1,000,000), `miliar`/`milyar` (×1,000,000,000). They only count when adjacent to the digits AND not followed by another letter, so "5km"/"5min" keep the letter as note text (amount 5, note "km …") instead of misreading the suffix. A named currency still wins over the IDR shorthand default ("10m usd" → 10,000,000 USD). Currency tokens are word-boundary + case-insensitive matched against a conservative map (usd/dollar, eur/euro, gbp/pound, jpy/yen, idr/rupiah/rp, sgd, aud, cad) — deliberately **no** bare "us"/"singapore"/"australian" so note words aren't eaten. Note cleaning strips the number+suffix token, currency words, and joiners "for/at/on" (keeps "in", etc.).

**Integration** (`AddTransactionViewModel.applyParsedDescription(predictor:)` + `parsedCurrencyCode` / `parseConfidence`):
- ⚠️ **Parses on COMMIT (the description field's return/"next" key), not per-keystroke.** The spec proposed live `onChange` parsing, but mutating the bound text mid-typing fights the cursor, and `AddTransactionView`'s `@FocusState` has documented transient blips that make focus-change parsing unsafe. `AutoFocusTextField.onSubmit` calls `applyParsedDescription` then advances focus to the amount field.
- Non-destructive: only for **new** entries (never rewrites a loaded transaction), fills the amount **only when `amountText` is empty**, and skips work when there's nothing to extract (leaves the live ML pass alone).
- Re-runs the existing ML pipeline (`triggerMLPrediction`) on the **cleaned** note.
- Writing the cleaned note back to `descriptionText` is a programmatic set, which does **not** re-fire the field's `onChange` (that's wired to `.editingChanged` = user input only) — so no recursion.

**Currency persistence caveat.** A parsed currency is stored on `Transaction.currencyCode` (`parsedCurrencyCode ?? AppCurrency.code`), matching the model's design intent (per-transaction currency for later FX). But there is **no FX conversion yet** — the whole UI renders amounts with an "Rp" prefix and sums them raw, so a `5 USD` transaction currently displays as "Rp 5" and adds 5 to IDR totals. Real conversion + display is Phase 9 (Multi-Currency & FX Rates, below). Until then, non-IDR parses are recorded correctly but shown/summed naively.

Tests: `AnkaTests/TransactionParserTests.swift` (Swift Testing) — the 6 spec-table cases + 4 edge cases (uppercase code, `k`+explicit-currency, substring-not-matched, empty). All pass.

---

## Multi-Currency & FX Rates (Phase 9)

**Design:**
- **Home Currency:** User sets one (default: IDR) in Settings → applies to all reports
- **Transaction Currency:** Each transaction logged in any currency (USD, EUR, GBP, JPY, INR, SGD, AUD, etc.)
- **Conversion:** All reports + charts convert to home currency using daily cached FX rates
- **Display on Transaction Row:** Original currency → Home currency (e.g., "USD 100 → IDR 1,550,000 (rate: 1 USD = 15.5K IDR)")

**Backend Architecture:**
- **Provider:** Supabase (free tier: 500MB database, unlimited API calls)
- **FX Data Source:** Open Exchange Rates (free API, 1,000 req/month)
- **Update Frequency:** Daily (1 call per day for all currency pairs)
- **Caching:** Rates stored in Supabase table, shared by all users globally
- **Fallback:** Last-known rate if API unavailable
- **Service:** `Services/FXRateService.swift` → `getRate(from:to:)` async throws Double

**UI Changes:**
- **Add Transaction:** Currency picker (dropdown, ~15 major currencies)
- **Settings:** "Home Currency" picker dropdown + "Refresh Rates" button (manual sync)
- **Reports:** All amounts auto-converted to home currency before charting
- **Transaction List:** Shows original amount + converted amount + rate used

- Fast Add Transaction (numpad, category, note, save in <5 taps)
- ML auto-categorization (3-layer: KeywordMatcher → UserModel → StarterModel)
- Home Screen + Lock Screen widgets (quick-add)
- Transaction list (grouped by day, swipe to delete, tap to edit)
- Monthly Reports (donut chart + bar chart — Swift Charts only)
- Category management (add/edit/delete/reorder)
- Multi-currency (per-transaction, daily FX rates cached from Supabase + Open Exchange Rates)
- Dark mode + adaptive appearance
- Biometric lock (Face ID / Touch ID)
- CSV + JSON export
- StoreKit 2 subscription with 14-day trial
- Onboarding: Welcome → Currency → First log → Paywall

---

## V1.1 Features (after launch validation)

- Siri / Shortcuts (App Intents)
- Apple Watch app (amount + category only)
- Receipt OCR (Apple Vision)
- Recurring transactions
- Simple category budgets
- 2–3 smart insights max

---

## Never Build

- Bank / e-wallet sync (no Plaid, no Open Banking)
- Balance tracking per account
- Multi-profile system
- Investment tracking
- Zero-based budgeting system
- Web companion app (MVP)
- Ads of any kind
- More than 2 chart types (donut + bar only)
- Android version (until iOS is profitable)
- Real-time FX rates (daily rates sufficient for personal expense tracking)

---

## Folder Structure

> **Updated to match the codebase as of this audit.** Differences from the original spec are called out inline.

```
Anka/
├── AnkaApp.swift              // entry point — builds ModelContainer via do/catch (held in @State
│                              //   as Result); on failure shows DataLoadErrorView (Try Again /
│                              //   Reset App Data). + seedOrMigrateCategories. (at Anka/ root, not App/)
├── App/
│   └── AppRouter.swift        // Today-only root (Stats is pushed); mirrors OS color scheme into AppearanceManager
├── DesignSystem/
│   ├── DSColor.swift
│   ├── DSFont.swift           // Dynamic-Type-aware tokens via UIFontMetrics. Adds dsHeroAmount
│   │                          //   (52/.black) + dsEmoji (24) — scaled, used by Today hero + row
│   ├── DSRadius.swift
│   ├── DSSpacing.swift        // scale: 4/8/12/16/24/32/48 + screenEdge (20, standard horizontal inset)
│   ├── Color+Hex.swift
│   ├── DateHelpers.swift      // startOfMonth, monthInterval, month labels
│   └── NumberFormatter+Amount.swift  // AppCurrency.code ("IDR") + idrShort / idrFormatted
├── Models/
│   ├── Transaction.swift                 // currencyCode defaults to AppCurrency.code
│   ├── Category.swift
│   ├── TransactionType.swift
│   └── SampleData.swift       // default categories + in-memory preview/test container
├── Views/
│   ├── Today/
│   │   ├── TodayView.swift              // ScrollView+LazyVStack (NOT a List); delete = context menu;
│   │   │                               //   "Delete Failed" alert on save error
│   │   ├── TodayViewModel.swift         // @MainActor @Observable; Task.detached aggregation;
│   │   │                               //   confirmDelete uses do/catch → deleteErrorMessage
│   │   └── CategoryFilterSheet.swift    // multi-select category filter + period pills + custom range
│   ├── AddTransaction/
│   │   ├── AddTransactionView.swift
│   │   ├── AddTransactionViewModel.swift  // @MainActor @Observable
│   │   └── CategoryPickerView.swift       // CategorySlotView + CategoryPickerSheet
│   │       // NOTE: NumpadView.swift from the original spec does not exist — the
│   │       //       numpad concept was replaced by the system keyboard + category pills.
│   ├── Stats/
│   │   ├── StatsView.swift                 // month stepper + summary hero (delta pill, daily avg,
│   │   │                                   //   income/net) + donut + category breakdown + weekly trend;
│   │   │                                   //   inherits Today's month one-way via `initialMonth`
│   │   ├── StatsViewModel.swift            // @MainActor; monthly aggregation off-main, month nav,
│   │   │                                   //   income/prev-month delta/daily avg/weekly avg
│   │   ├── CategoryBreakdownRow.swift      // ranked row: emoji + name + proportion bar + amount + %
│   │   └── WeeklyTrendChartView.swift      // horizontal bar chart + avg RuleMark + tap-to-select week
│   ├── Settings/
│   │   ├── SettingsView.swift              // native List, sectioned
│   │   ├── SettingsViewModel.swift         // @Observable @MainActor
│   │   ├── CategoryManagementView.swift    // sub-menu: list + swipe-delete + drag-reorder
│   │   ├── AddEditCategorySheet.swift      // modal form for add/edit/delete
│   │   ├── AppearanceSettingsView.swift    // sub-page: Mode + Dark Variant
│   │   ├── BackupSettingsView.swift        // rolling JSON backups: list / restore / delete
│   │   ├── DataManagementView.swift        // CSV/JSON import + export entry point
│   │   ├── ExportSheet.swift               // share-sheet for CSV/JSON export
│   │   ├── ImportPreviewSheet.swift        // parsed-rows preview before committing import
│   │   └── ImportSummarySheet.swift        // post-import result summary
│   └── AppLock/
│       ├── AppLockView.swift               // biometric primary, PIN fallback
│       └── PINSetupSheet.swift             // two-step PIN enrollment
├── Components/               // reusable UI, no business logic
│   ├── DonutChartView.swift            // ported from Spendy; selection lifted to a `selectedID`
│   │                                   //   binding (syncs with Stats breakdown rows) + emoji on
│   │                                   //   CategorySpendData. Gestures/ratios/haptics still verbatim.
│   ├── TransactionRow.swift            // extracted row: emoji + name/desc + AmountLabel;
│   │                                   //   onEdit/onDelete callbacks + matchedTransitionSource + contextMenu
│   ├── AmountLabel.swift               // signed "Rp …" capsule; (amount: Double, type: TransactionType)
│   ├── DateRangePicker.swift           // custom date-range UI for the "custom" period filter
│   └── AutoFocusTextField.swift        // UIViewRepresentable — Mail-style first-responder timing
│       // NOTE: SectionHeader.swift (specced) was never built; ComponentsPlaceholder.swift removed.
├── Services/
│   ├── CategoryPredictor.swift       // ported from Spendy (3-layer pipeline)
│   ├── CategoryMLTrainer.swift       // ported from Spendy (on-device CreateML)
│   ├── KeywordMatcher.swift          // ported from Spendy
│   ├── PlatformPaths.swift           // App Group ID + container URL (Anka IDs)
│   ├── TransactionFilterEngine.swift // ported, gated #if ENABLE_TRANSACTION_FILTER_ENGINE
│   ├── AppLockManager.swift          // ported from Spendy — pinKey "ankaPINCode"; biometric
│   │                                 //   state cached (shared LAContext) via refreshBiometricState()
│   ├── KeychainHelper.swift          // ported from Spendy — service "nc.Anka"
│   ├── AppearanceManager.swift       // @MainActor @Observable — mode + dark variant
│   ├── BackupService.swift           // versioned JSON export/import, dedup by transaction id
│   ├── AutoBackupService.swift       // rolling JSON backups (App Group + Documents, keep 7)
│   │                                 //   ⚠️ header claims save/delete + foreground auto-triggers,
│   │                                 //      but performBackup() is only called manually from
│   │                                 //      BackupSettingsView — the auto-triggers are NOT wired.
│   ├── CSVService.swift              // CSV export + parse-with-preview (no direct DB writes)
│   ├── WidgetDataWriter.swift        // writes shared App Group UserDefaults
│   └── WidgetSharedTypes.swift       // shared by main app + AnkaWidgets target
│       // NOTE: FXRateService.swift (Supabase + Open Exchange Rates) is specced for Phase 9
│       //       and does NOT exist yet.
└── Resources/
    ├── Assets.xcassets
    └── StarterCategoryClassifier.mlmodelc  // ported from Spendy
```

---

## Files Ported from Spendy

Copy these verbatim from the Spendy project — do not rewrite:
- `CategoryPredictor.swift` → update App Group ID to `group.com.nc.Anka`
- `CategoryMLTrainer.swift` → update App Group ID
- `KeywordMatcher.swift` → no changes needed
- `TransactionFilterEngine.swift` → no changes needed
- `AppLockManager.swift` → update Keychain key to `"ankaPINCode"`
- `DSFont.swift` → clean up tokens to 8–10 only
- `StarterCategoryClassifier.mlmodelc` → drag into Resources/
- `DonutChartView.swift` (Spendy `Views/Charts/`) → swap `Color.spendyCoral` → `DSColor.accent`; preserve `innerRatio: 0.78`, drag-vs-swipe deadzone (12pt), spring/easeInOut timings, haptic, raw font sizes (13/23/12) — these define the chart's feel. **Stats-redesign deviation (approved):** selection state is no longer internal `@State` — it's a `@Binding var selectedID: String?` so the donut + Stats category list stay in sync, and `CategorySpendData` gained an `emoji` field. Gesture math / ratios / haptics / timings are untouched.

Do NOT port: any View files, FirestoreSyncService, ProfileManager, InsightEngine, RecurringDetector, BackupService, CSVService, DashboardV2/V3.

---

## Phase Status

| Phase | Name | Status |
|---|---|---|
| 0 | Project Setup + Design System | ✅ Done |
| 1 | Data Models | ✅ Done |
| 2 | Add Transaction | ✅ Done (Spendy V2-adapted layout, SwiftData persistence wired; tags + ML + edit/delete added) |
| 3 | Today View | ✅ Done (Expense/Income/Total switcher, pinned hero, Stats button) |
| 4 | Stats View | ✅ Done · **Redesigned** (month stepper, summary hero w/ MoM delta + daily avg + income/net, donut with row↔slice sync, category breakdown list, weekly trend w/ avg line; inherits Today's month one-way, zooms from the pie toolbar icon) |
| 5 | Settings + Categories | ✅ Done |
| 6 | ML Auto-Categorization | ✅ Done |
| 7 | Widgets | ✅ Done |
| 8 | App Lock | ✅ Done |
| 9 | Subscription | ⬜ Not started |
| 10 | iCloud Sync | ⬜ Not started |

**Shipped outside the numbered plan (no dedicated phase number):**

| Feature | Status |
|---|---|
| Search & Filter on Today (text search + category multi-select + period/custom range) | ✅ Done (see "Search & Filter" section; swipe-delete bug outstanding) |
| Appearance (theme + dark variant via AppearanceManager) | ✅ Done |
| Backup & Restore (rolling JSON, manual trigger) | ✅ Done (auto-triggers not wired) |
| Import & Export (CSV + JSON, with preview) | ✅ Done |
| Onboarding (Welcome → Speed → Clarity → Trial; `Views/Onboarding/`, gated by `anka.hasCompletedOnboarding`) | ✅ Done — paywall prices + "Start Trial" + Demo Mode are **placeholders** (StoreKit 2 is Phase 9, demo-mode 24h reset not built; both buttons just complete onboarding). Settings → **Developer → Replay Onboarding** flips the flag back to re-show it (dev tool while in active development; only mutates the flag, never SwiftData — existing transactions/categories are preserved). |
| NLP description parsing (`Services/TransactionParser.swift`) | ✅ Done — see "NLP Description Parsing" section. Parses amount (+ English `k`/`m`/`b` and Indonesian `rb`/`jt`/`miliar` magnitude shorthand) + currency + note out of the Add-Transaction description on commit; ML re-categorizes the cleaned note. 22 unit tests in `AnkaTests/TransactionParserTests.swift` (all pass). |

Update status to: ⬜ Not started / 🔄 In progress / ✅ Done / ❌ Issue

> **Code health:** a full audit lives in `Anka_Code_Audit.md` (repo root).
>
> **✅ Fixed since the audit:**
> - `try!` ModelContainer init → `do/catch` + `DataLoadErrorView` recovery screen (Try Again / Reset App Data).
> - `AddTransactionViewModel` now `@MainActor @Observable`.
> - Swipe-to-delete no-op on Today → replaced with `.contextMenu` (Edit/Delete) on `TransactionRow`.
> - Currency default inconsistency → `Transaction` + save path both use `AppCurrency.code`.
> - `AppLockManager` biometric checks no longer allocate an `LAContext` per render (cached + `refreshBiometricState()`).
> - Removed dead `SettingsViewModel.darkModeEnabled`; deleted scratch `test2.swift` / `test3.swift`.
> - ML negative-correction over-logging in `handleDescriptionChange` removed (now only on explicit deselect).
> - `DSSpacing.screenEdge` token added + 14 raw `20` horizontal-padding sites migrated.
> - `DSFont.dsHeroAmount` + `dsEmoji` (Dynamic-Type-scaled) added; Today hero amount + row emoji migrated.
> - Extracted reusable `TransactionRow` + `AmountLabel` components; deleted `ComponentsPlaceholder.swift`.
> - `TodayViewModel.confirmDelete` silent `try?` → `do/catch` + "Delete Failed" alert.
>
> **Still open:** AutoBackup auto-triggers not wired; Stats has no category filter (month comparison + income/net summary now shipped in the Stats redesign); Today search doesn't cover tags/paymentMethod; broader design-token adoption (remaining hardcoded font sizes outside DonutChart); `SectionHeader` component never built.

---

## Claude Code Session Rules

1. **Always read this file first** before any task
2. **One phase per session** — do not combine phases
3. **Use DSColor, DSFont, DSRadius, DSSpacing tokens always** — never hardcode hex, font sizes, or corner radii
4. **No Firestore, no Firebase, no backend code** — ever
5. **No iCloud/CloudKit** until Phase 10 is explicitly started
6. **Do not modify ported files** (CategoryPredictor, KeywordMatcher, etc.) unless explicitly asked
7. **Verify before moving on** — list all files created or modified at the end of each task
8. **No feature creep** — build only what is listed for the current phase

---

## Key Decisions Log

| Decision | Choice | Reason |
|---|---|---|
| Sync | Local SwiftData → iCloud later | No paid dev account yet |
| Multi-profile | None | Single-user app |
| Account tracking | Tags + paymentMethod field only | No balance complexity |
| Bank sync | Never | Too costly, not the product |
| Charts | Donut + bar (Swift Charts) | Simplicity |
| Paywall | Hard paywall, 14-day trial | 5x better conversion |
| Testing | Swift Testing + XCTest UI | Modern Swift stack |
| Platform | iOS only | Focus, macOS later if needed |
| Subscription | StoreKit 2 native | No RevenueCat needed at this scale |
| AI scope | ML categorization + OCR only | On-device, free, private |
| Multi-Currency | Per-transaction, convert all to home currency in reports | Like YNAB; simplifies charts + totals |
| FX Rates | Daily cached via Supabase + Open Exchange Rates | Free at MVP scale, no real-time complexity |
| Home Currency | Single base currency for all reports | Clean reporting, no ambiguity |
