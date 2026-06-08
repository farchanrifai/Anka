# Anka — Claude Code Project Context

> Read this file at the start of every Claude Code session before doing anything.
> Update the Phase Status section after each completed phase.

---

## App Identity

- **Name:** Anka
- **Platform:** iOS only (no macOS, no Android)
- **Minimum iOS:** 26.0 (uses Liquid Glass tab bar APIs: `role: .search` detached Add button, `.tabBarMinimizeBehavior`)
- **Bundle ID:** com.nc.anka
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
- All ViewModels are `@Observable` and `@MainActor`
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

### Fonts (DSFont.swift) — ported from Spendy, cleaned to 8–10 tokens
- dsHero, dsTitle, dsHeadline, dsSubhead, dsBody, dsCaption, dsBadge
- All use `Font.system(size:)` — no custom fonts at MVP

### Radius (DSRadius.swift)
- `dsSmall` = 8
- `dsMedium` = 14
- `dsLarge` = 20

### Spacing (DSSpacing.swift)
- Scale: 4, 8, 12, 16, 24, 32, 48

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
currencyCode: String // default "USD"
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
- Left pill/island: **Today** only — the Reports tab was removed; **Stats** is reached via the "Stats →" button in the Today hero, pushed onto Today's `NavigationStack`
- Right detached button: **Add** — `role: .search` detaches it from the pill; intercepted via `onChange` (opens sheet, restores previous tab, does NOT navigate)
- `.tabBarMinimizeBehavior(.onScrollDown)` — bar minimizes as content scrolls down

**Settings:** floating gear icon (top-right) on **Today** → presents `SettingsView` as a sheet (modal, not a tab). Native `List` with sections: **General** (Categories → push to `CategoryManagementView`, Default Currency) · **Appearance** (Dark Mode toggle) · **Data** (Export stub) · **About** (version). `CategoryManagementView` is the sub-menu: native List split into Expense / Income sections, swipe-to-delete via `.onDelete`, drag-to-reorder via `.onMove` + `EditButton`, `+` toolbar button presents `AddEditCategorySheet` for add/edit/delete.

**Add Transaction flow (Spendy-adapted layout):** full-screen modal, top→bottom:
- Top bar: `Cancel` capsule (left) · `•••` options-placeholder capsule (right, inert — recurring lives in a later phase)
- Centered amount: `IDR` prefix + whole-number value with thousands separator (e.g. `IDR 12,345`), animated `.numericText()` transition
- Centered `Add note` text field (focuses the system keyboard; numpad fades out while editing)
- Flexible spacers push the action row + numpad to the bottom
- Category + Date + Save row (all 48 pt tall): compact category slot (opens picker **sheet** — segmented Expenses/Income tabs + scrollable list, `.medium`→`.large` detents) · functional date pill (`DD`/`MON`, tap = inline `DatePicker`) · coral Save capsule (disabled until amount + category set)
- Numpad: 1–9, then note-key (✎) · 0 · `⌫`. No per-key backgrounds; each key is a full-cell tap target and the grid expands to fill available height. IDR amounts are whole numbers, so the note key replaces the decimal.

Default currency: `IDR`. State held in-view via `@State` (no ViewModel). No persistence yet — Save just dismisses (Phase 3 wires SwiftData).

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

The old `darkModeEnabled` toggle in `SettingsViewModel` (a leftover from Phase 5) was non-functional and is now superseded by the AppearanceManager — the field can be removed from the VM when convenient.

## Today View — Search behavior gotcha

`TodayView` uses iOS-26's bottom-toolbar search pattern: `.searchable(text:)` + `DefaultToolbarItem(kind: .search, placement: .bottomBar)` + `.searchToolbarBehavior(...)`. By default, activating the search field triggers `UISearchController`'s **search-presentation mode**, which slides the underlying content up out of view (it assumes the search results will replace the original content). This caused the sticky header (Expense/Income/Total + amount + Stats) to disappear when the keyboard came up.

**Fix:** `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the `.searchable` chain. iOS 18.2+ modifier that keeps the underlying content in place while search is active. This is **not** a keyboard-avoidance issue — `.ignoresSafeArea(.keyboard)` and `.scrollDismissesKeyboard(.never)` do not help, since the shift comes from `UISearchController` not from the keyboard inset itself.

Cosmetic UIKit warnings persist (`SearchBarHidesWhenScrolling-default` vs `-explicit`, `Adding UIKitToolbar as subview...`, constraint conflicts on `_UIButtonBarButton`) — these are known SwiftUI↔UIKit bridge noise from the bottom-toolbar search pattern in iOS 26 and don't affect runtime behavior.

## App Lock (Phase 8)

`Services/AppLockManager.swift` is `@MainActor @Observable`, owned by `AnkaApp` as `@State` and injected via `.environment(lockManager)`. Single source of truth for:

- `appLockEnabled: Bool` — persisted to `UserDefaults` under `anka.appLockEnabled` (the `didSet` writes through automatically)
- `isLocked: Bool` — transient, flips between launches/foreground/background
- `hasPIN: Bool` — derived from `KeychainHelper.read(forKey: "ankaPINCode") != nil`
- Biometric helpers: `biometricType`, `canUseBiometrics`, `authenticateWithBiometrics() async -> Bool`
- PIN: `savePIN`, `removePIN`, `verifyPIN`

`KeychainHelper` uses service `nc.Anka` (separate from the App Group ID).

**Lock gate at app root** — `AnkaApp.body` wraps `AppRouter` in a `ZStack` and overlays `AppLockView` when `lockManager.isLocked` is true. `.onChange(of: scenePhase)` calls `lockManager.lock()` on `.background`/`.inactive`, but `lock()` itself bails when `appLockEnabled == false` OR `hasPIN == false` — so the user can never be stranded.

**PIN is mandatory when enabling.** The Settings toggle won't flip `appLockEnabled` to true unless a PIN exists; it presents `PINSetupSheet` first. Biometric remains the fast path, PIN is fallback.

**Settings security section** lives in the existing native `List` (Settings → Section "Security"):
- Toggle: "Face ID & PIN" / "Touch ID & PIN" / "App Lock (PIN)" depending on `biometricType`
- "Change PIN" — re-runs `PINSetupSheet`
- "Remove PIN" — confirmation dialog, then `removePIN()` + `appLockEnabled = false` together

**Lock screen UX** (`AppLockView`):
- Auto-prompts biometric once on first appearance via `.task`
- If biometric fails/cancels, falls through to PIN input automatically
- 4-digit PIN auto-submits on the 4th character; wrong PIN clears + error haptic
- "Use PIN instead" / "Back to Face ID" toggles between the two methods

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
- On manual deselect of an ML-picked category: logs negative correction (`actual: nil`).
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

- Fast Add Transaction (numpad, category, note, save in <5 taps)
- ML auto-categorization (3-layer: KeywordMatcher → UserModel → StarterModel)
- Home Screen + Lock Screen widgets (quick-add)
- Transaction list (grouped by day, swipe to delete, tap to edit)
- Monthly Reports (donut chart + bar chart — Swift Charts only)
- Category management (add/edit/delete/reorder)
- Multi-currency (per-transaction, no live rates at MVP)
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
- Live exchange rates
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

---

## Folder Structure

```
Anka/
├── App/
│   ├── AnkaApp.swift          // entry point, ModelContainer setup
│   └── AppRouter.swift        // tab bar + sheet state
├── DesignSystem/
│   ├── DSColor.swift
│   ├── DSFont.swift           // ported from Spendy
│   ├── DSRadius.swift
│   └── DSSpacing.swift
├── Models/
│   ├── Transaction.swift
│   └── Category.swift
├── Views/
│   ├── Today/
│   │   ├── TodayView.swift
│   │   └── TodayViewModel.swift
│   ├── AddTransaction/
│   │   ├── AddTransactionView.swift
│   │   ├── AddTransactionViewModel.swift
│   │   ├── NumpadView.swift
│   │   └── CategoryPickerView.swift
│   ├── Stats/
│   │   ├── StatsView.swift                 // donut chart + top categories per month
│   │   └── StatsViewModel.swift            // monthly aggregation, swipe-driven month nav
│   ├── Settings/
│   │   ├── SettingsView.swift              // native List, sectioned
│   │   ├── SettingsViewModel.swift         // @Observable @MainActor
│   │   ├── CategoryManagementView.swift    // sub-menu: list + swipe-delete + drag-reorder
│   │   ├── AddEditCategorySheet.swift      // modal form for add/edit/delete
│   │   └── AppearanceSettingsView.swift    // sub-page: Mode + Dark Variant
│   └── AppLock/
│       ├── AppLockView.swift               // biometric primary, PIN fallback
│       └── PINSetupSheet.swift             // two-step PIN enrollment
├── Components/               // reusable UI, no business logic
│   ├── TransactionRow.swift
│   ├── AmountLabel.swift
│   ├── SectionHeader.swift
│   └── DonutChartView.swift            // ported verbatim from Spendy — pixel-perfect
├── Services/
│   ├── CategoryPredictor.swift       // ported from Spendy (3-layer pipeline)
│   ├── CategoryMLTrainer.swift       // ported from Spendy (on-device CreateML)
│   ├── KeywordMatcher.swift          // ported from Spendy
│   ├── PlatformPaths.swift           // App Group ID + container URL (Anka IDs)
│   ├── TransactionFilterEngine.swift // ported, gated #if ENABLE_TRANSACTION_FILTER_ENGINE
│   ├── AppLockManager.swift          // ported from Spendy — pinKey "ankaPINCode"
│   ├── KeychainHelper.swift          // ported from Spendy — service "nc.Anka"
│   ├── AppearanceManager.swift       // @Observable — mode + dark variant
│   ├── WidgetDataWriter.swift        // writes shared App Group UserDefaults
│   └── WidgetSharedTypes.swift       // shared by main app + AnkaWidgets target
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
- `DonutChartView.swift` (Spendy `Views/Charts/`) → only swap `Color.spendyCoral` → `DSColor.accent`; preserve `innerRatio: 0.78`, drag-vs-swipe deadzone (12pt), spring/easeInOut timings, haptic, raw font sizes (13/23/12) — these define the chart's feel

Do NOT port: any View files, FirestoreSyncService, ProfileManager, InsightEngine, RecurringDetector, BackupService, CSVService, DashboardV2/V3.

---

## Phase Status

| Phase | Name | Status |
|---|---|---|
| 0 | Project Setup + Design System | ✅ Done |
| 1 | Data Models | ✅ Done |
| 2 | Add Transaction | ✅ Done (Spendy V2-adapted layout, SwiftData persistence wired) |
| 3 | Today View | ✅ Done (Expense/Income/Total switcher, pinned hero, Stats button) |
| 4 | Stats View | ✅ Done (Spendy donut chart ported pixel-perfect; replaces old Reports) |
| 5 | Settings + Categories | ✅ Done |
| 6 | ML Auto-Categorization | ✅ Done |
| 7 | Widgets | ✅ Done |
| 8 | App Lock | ✅ Done |
| 9 | Subscription | ⬜ Not started |
| 10 | iCloud Sync | ⬜ Not started |

Update status to: ⬜ Not started / 🔄 In progress / ✅ Done / ❌ Issue

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
