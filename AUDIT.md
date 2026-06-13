# Anka — Full Codebase Audit Report

Date: 2026-06-13 · Scope: every Swift file in `Anka/`, `AnkaWidgets/`, `AnkaTests/`, `AnkaUITests/`, plus entitlements and project build settings.

Severity legend: 🔴 **Critical** (crash, data loss, or shipping blocker) · 🟠 **High** (real user-facing bug or major gap) · 🟡 **Medium** (correctness/quality issue) · 🟢 **Low** (polish, debt, nice-to-have).

---

## 1. Crash & Shipping Blockers

### S1 🔴 Missing `NSFaceIDUsageDescription`
`AppLockManager.authenticateWithBiometrics()` calls `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`, but the generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`) has no `INFOPLIST_KEY_NSFaceIDUsageDescription`. On a Face ID device, the first unlock attempt **kills the app**. The app-lock feature is currently untestable/unshippable on real hardware.
**Fix:** add `INFOPLIST_KEY_NSFaceIDUsageDescription` to both Debug/Release configs of the app target.

### X1 🔴 iPad crash in CSV export
`ExportSheet.shareFiltered()` presents a `UIActivityViewController` with no `popoverPresentationController.sourceView`. `TARGETED_DEVICE_FAMILY = "1,2"` — on iPad this is a guaranteed `UIPopoverPresentationController` crash.
**Fix:** replace the UIKit hack with SwiftUI `ShareLink` (write the temp file first, share its URL), or set a popover anchor.

### U1 🔴 App icon is empty
`Assets.xcassets/AppIcon.appiconset` contains only `Contents.json` — no images. App Store submission will be rejected; home screen shows the placeholder grid.

### U7/U8 🟠 Fake paywall shipping risk
`OnboardingPaywallView` shows hardcoded prices, a "Start 14-Day Free Trial" button that purchases nothing, a "Demo Mode" promising 24h data resets that don't exist, and a non-tappable "Restore Purchases · Terms · Privacy" text row. Documented as Phase 9 placeholders — fine for dev, but must be wired (StoreKit 2) or removed before any TestFlight/external build.

---

## 2. Data Integrity & Persistence

### D1 🔴 Deleting a category silently deletes all its transactions
`Category.transactions` uses `@Relationship(deleteRule: .cascade, ...)`. Both deletion paths — swipe-to-delete in `CategoryManagementView.delete(from:at:)` and the trash button in `AddEditCategorySheet.deleteEditing()` — delete with **no warning and no mention of the transactions**. A user deleting an unused-looking category can wipe years of records. The migration code in `AnkaApp` even works around this exact cascade ("`.cascade` would otherwise delete them").
**Fix:** change the delete rule to `.nullify` (transactions become "Uncategorized", matching the migration behavior), and add a confirmation dialog stating how many transactions will be affected. Optionally offer "reassign to another category".

### D2 🔴 Auto-backup never runs automatically
`AutoBackupService`'s header claims it's "Triggered after every transaction save/delete (no gate) and on app foreground (24-hour gate via shouldBackup())" — but a project-wide search shows `performBackup` is only called from the manual "Back Up Now" button, and `shouldBackup()` is **never called anywhere**. The safety net the Backup screen advertises ("Status: Enabled", "Up to 7 backups are kept automatically") does not exist. Combined with D1, real data loss is one category-delete away.
**Fix:** trigger `performBackup` after transaction save/delete (e.g. from the save/delete paths or a scene-phase `.background` hook gated by `shouldBackup()`), and call it on foreground with the 24h gate as documented.

### D3 🟠 Backups don't preserve categories; restore corrupts category types
The backup payload stores only `categoryName` per transaction. `BackupService.resolveCategory` recreates any missing category as `type: .expense`, emoji 📦, gray, sortOrder 999. Restoring on a fresh install turns **Salary/Freelance/Investment into expense categories**, breaking income/expense math everywhere. Emoji, colors, and ordering are also lost.
**Fix:** add a `categories` array (name, emoji, colorHex, type, sortOrder) to the payload, bump `currentVersion` to 2, restore categories first, keep v1 read compatibility (fall back to transaction `type` as a heuristic for category type).

### D4 🟠 Wrong hardcoded `"USD"` currency fallbacks
`BackupService.restore` (both variants) and `CSVService.commit` default missing currency to `"USD"` in an IDR-first app (`AppCurrency.code == "IDR"`). Restored/imported rows silently become USD.
**Fix:** use `AppCurrency.code`.

### D5 🟠 Multi-currency amounts are summed as if they were IDR
`TransactionParser` happily produces `amount: 5, currencyCode: "USD"`, and `Transaction.currencyCode` is persisted — but every aggregation (`expenseTotal`, stats, widgets, day headers, search) sums raw `amount` and renders "Rp". A "5 dollar coffee" entry shows as Rp 5 and skews every chart. The per-transaction currency is never displayed anywhere either.
**Fix (decide one):** (a) MVP: drop foreign-currency capture — parser always returns IDR, remove `currencyCode` from the UI surface; or (b) keep it: show the original currency on rows, and either exclude non-IDR from totals with a footnote or apply a stored conversion rate. (a) is recommended until currency support is a real feature.

### D6 🟠 Decimal-comma locale bug in amount entry (target market!)
`AddTransactionViewModel.parsedAmount` strips all `","` as thousands separators. On an Indonesian-locale device, `.decimalPad` shows **comma as the decimal key** — typing `1,5` yields **15**, a 10× error for the app's primary audience. `formattedAmountDisplay` likewise only recognizes `"."`. `TransactionParser.firstNumber` has the same comma assumption.
**Fix:** interpret separators via `Locale.current.decimalSeparator` (or parse with a locale-aware `NumberFormatter`), and normalize in the parser.

### D7 🟡 CSV round-trip is broken
`CSVService.escape` doubles quotes and can emit embedded newlines, but `parseCSVLine` neither unescapes doubled quotes nor handles multi-line quoted fields (file is pre-split on newlines). Exporting a note like `He said "hi"` or one containing a comma+quote combination then re-importing produces corrupted fields.
**Fix:** make the parser a proper state machine over the whole file (handle `""` and quoted newlines), and unescape on read.

### D9 🟡 CSV import has no duplicate detection
`CSVService.commit` inserts every row unconditionally. Re-importing the same file doubles the dataset (backup restore dedupes by UUID; CSV has nothing).
**Fix:** detect probable duplicates (date+amount+type+note) at preview time, show them as "skipped (duplicate)" with an override toggle.

### D8 🟡 Month/period boundary gaps
`Date.endOfMonth` is `startOfNextMonth - 1 second`, so `monthInterval` excludes the last second of the month and `DateInterval.contains` excludes the exact end instant. The custom-range path in `TodayViewModel.periodInterval` has the same `23:59:59` pattern. Transactions written at the boundary (e.g. imported with date-only midnight of the 1st vs end-of-day) can fall into neither month.
**Fix:** use half-open intervals everywhere — `start ≤ date < startOfNextMonth` — instead of "-1 second" end dates.

### D10 🟡 Total mode + category filter shows wrong hero amount
`TodayViewModel.heroAmount`: when categories are selected, it sums `filteredTransactions` regardless of type — in `.total` mode income and expense are **added together** instead of netted.
**Fix:** net (income − expense) in `.total` mode within the filtered branch.

### D11 🟢 Migration flag set even when saves fail
`seedOrMigrateCategories` uses `try? context.save()` and then sets `categoryMigrationKey` unconditionally — a failed save permanently skips the migration. Same `try?`-swallowing pattern appears in `CategoryManagementView` and `AddEditCategorySheet` (failed saves are invisible to the user).
**Fix:** only set the flag on successful save; surface save errors in category management.

### X2 🟡 Edits may not propagate to dashboard/widget
`TodayView.onChange(of: allTransactions)` relies on array equality of `@Model` class references. Editing only a transaction's *amount* (no resort, same identities) may not fire the `onChange`, leaving `dataVersion` stale (cached `groupedByDay` totals, day headers) and `WidgetDataWriter` not called. Likewise backup/CSV restore done in Settings updates widgets only after Today's query happens to re-fire.
**Fix:** verify on device; safest is an explicit "data changed" notification posted after every successful save/delete/import/restore that bumps the VM and rewrites widget data centrally.

---

## 3. Security

### S2 🟠 PIN: no brute-force protection, plaintext, default keychain class
- `AppLockView.attemptPINUnlock` allows unlimited rapid attempts (4 digits = 10k tries, trivially scriptable with a HID device).
- The PIN is stored as plaintext in the keychain with no `kSecAttrAccessible` attribute (defaults to `WhenUnlocked`, and is **not** `ThisDeviceOnly` — it can migrate via encrypted backups to another device).
**Fix:** store a salted hash (or at least set `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), add escalating lockout delays after N failed attempts (persisted, so relaunch doesn't reset).

### S3 🟡 KeychainHelper silently ignores all OSStatus results
`savePIN` can fail (e.g. device locked, keychain error) while `hasPIN` flips to `true` → user enables App Lock with no PIN actually stored → locked out forever (biometric-fail path then has nothing to verify).
**Fix:** return `Bool`/throw from save/delete; only set `hasPIN`/`appLockEnabled` on success.

### S4 🟢 Lock triggers on `.inactive`
Pulling down Control Center or a notification re-locks the app immediately. Most finance apps lock on `.background` only, or offer a grace period ("Require after 1 min"). Product decision — consider a setting.

---

## 4. UX Gaps

### U2 🟠 Month navigation on Today is swipe-only (undiscoverable + inaccessible)
The only way to change months on the dashboard is the horizontal swipe over the list. There is no visible affordance, no VoiceOver path, no way back to "now" except swiping repeatedly. The period pill opens the filter sheet, which offers 3M/6M/year/custom — but **not** single-month selection. `StatsViewModel.resetToCurrentMonth()` exists and is never called.
**Fix:** make the period pill (or a tap on the month name) show a month menu/stepper; show a "Back to <current month>" chip when browsing the past; reuse `resetToCurrentMonth` in Stats (e.g. tap the month label).

### U10 🟡 Custom categories can't choose a color
`SettingsViewModel.newCategoryColor` exists and is persisted, but `AddEditCategorySheet` has no color control — every user-created category is coral `F26666`. The Stats donut then renders multiple same-color slices.
**Fix:** add a color swatch row (preset palette) to the sheet. Also validate the emoji field (currently a free-text `TextField` accepting any string, see U11) and guard against duplicate names (ML matching is name-based).

### U4 🟡 Currency is hardcoded "Rp"/"IDR" in ~10 views and unconfigurable
Hero header, `AmountLabel`, `DayHeaderView`, Stats, widgets, AddTransaction all hardcode "Rp"/"IDR" strings even though `AppCurrency.code` exists. Settings shows "Default Currency: IDR" as a dead, non-tappable row — looks broken.
**Fix:** route all symbols through one formatter helper; either build the currency setting or remove the dead Settings row.

### U6 🟡 Search edge cases
- Search with no hits shows the generic "No Matches Found" empty state whose "Clear Filters" button only clears *category* filters, not the search text.
- Search doesn't match tags (`tx.tags` ignored in `displayedGroupedByDay`).
**Fix:** add a search-specific empty state + clear-search action; include tags in the match predicate.

### U14 🟡 Destructive delete with no undo
Transaction delete is confirm-dialog only. A misplaced tap + reflex confirm loses data (no trash, no undo). Consider an "Undo" toast (keep the snapshot, reinsert on tap) instead of/in addition to the alert.

### U16 🟢 Backup screen misleads
"Auto-Backup — Status: Enabled" is hardcoded text for a feature that (per D2) never runs and has no toggle. Fix copy alongside D2.

### U15 🟢 iPad support is nominal
Universal device family with iPhone-only layouts (fixed 280pt charts, single column, sheet metrics). Either set device family to iPhone-only for MVP or do an iPad layout pass.

### U17 🟢 Misc
- `SettingsView` "Developer" section (Replay Onboarding) ships in Release — wrap in `#if DEBUG`.
- `@AppStorage("anka.hasCompletedOnboarding")` defaults differ between `AnkaApp` (false) and `SettingsView` (true) — harmless today, fragile.
- PIN setup accepts `0000`/`1234` with no weak-PIN nudge.

---

## 5. Accessibility

### AC1 🟠 Half the type scale ignores Dynamic Type
`DSFont` tokens **without** `relativeTo:` are fixed-size: `dsHero`, `dsDisplay`, `dsLargeTitle(+Bold)`, `dsTitle`, `dsTitle2(+Bold)`, `dsTitle3`, `dsHeadline`, `dsSubhead`, `dsBody`, `dsBodyMedium`, `dsCaption`, `dsBadge`. These are used in the most important places — AddTransaction description/amount fields (`dsTitle`), body text app-wide, the Stats hero (`dsTitle2Bold`). Users with larger text sizes get no scaling in exactly the core flows. (The file's own header comment claims all tokens scale — it's wrong.)
**Fix:** add `relativeTo:` anchors to every remaining token; spot-check layouts at XL and AX sizes (`minimumScaleFactor` already protects the hero).

### AC2 🟡 Donut chart is invisible to VoiceOver
The clear gesture layer sits over the chart; slices have no accessibility elements, selection has no announcement. The breakdown rows below partially compensate but have no `accessibilityValue` for percent/amount semantics.
**Fix:** add `accessibilityElement`s (label: category, value: amount + percent) or an `AXChartDescriptor`; ensure breakdown rows read "Groceries, Rp 1,840,000, 38 percent".

### AC3 🟡 "Hidden" balance isn't hidden from VoiceOver
`isAmountHidden` only applies a visual blur — VoiceOver still reads the full amount, and the tap target has no label explaining the toggle (it also does double duty as "clear filter", which is undiscoverable).
**Fix:** when hidden, set `.accessibilityLabel("Balance hidden")`/`.privacySensitive()`; give the toggle an explicit a11y action.

### AC5 🟢 No Reduce Motion handling
Onboarding bloom/spin choreography, shake effect, repeating sparkle `symbolEffect`, blur transitions — none check `accessibilityReduceMotion`.

### AC6 🟢 Contrast check
Coral `#F26666` on white for small text (links/labels) is ≈3.2:1 — below WCAG AA for body sizes. Audit small coral text usages.

---

## 6. ML / Prediction Quality

### X6 🟡 KeywordMatcher substring false positives
Layer A2 uses `lower.contains(keyword)` with no word boundaries: "rep**air**" → Home, "**teh**eran"/"theory"-style hits → Coffee, "pre**mie**re" → Eating Out, "**giant**ic" → Groceries, "s**teh**oscope" etc. The fuzzy layer carefully guards short tokens, but the exact layer doesn't.
**Fix:** match on word boundaries for short keywords (≤4 chars at minimum: "air", "teh", "mie", "tol", "ipl", "kost", "sewa", "hero", "giant", "token", "solar"); keep substring matching for brand names.

### P6 🟡 Correction log grows forever
`logCorrection` decodes/appends/re-encodes the whole array into UserDefaults on every correction, unbounded. Years of use = slow saves + stale negative signals over-weighting training (entries are doubled at train time).
**Fix:** cap (e.g. last 500), and age out entries already absorbed by a training run.

### 🟢 Notes
- `Prediction.shouldShowChip` exists but no chip UI is implemented — the 0.60–0.85 band silently auto-assigns nothing; either build the chip or fold the band into auto-assign-with-undo.
- `CategoryPredictor`/`CategoryMLTrainer` duplicate `amountBucket` — extract one shared helper (drift here silently breaks the model contract).
- Renaming a default category in Settings silently severs ML auto-categorization (labels are name-coupled — `SampleData` documents this); warn in the edit sheet.

---

## 7. Widgets

### W1 🟡 Widget shows stale "Today" after midnight
`WidgetDataWriter` stores today's totals; the 15-min timeline just re-reads the same stored numbers. After midnight (app not opened), the widget keeps showing **yesterday's** spend labeled "Today".
**Fix:** store the snapshot date; in `loadEntry`, zero the totals (and clear recents) when the stored date isn't today; add a timeline entry at next midnight.

### W2 🟢 Wrong currency symbol
`AnkaLockScreenWidgetView` uses SF Symbol `indianrupeesign` (₹, Indian rupee) for an IDR app. Use a text "Rp" or a neutral symbol.

### W3 🟢 No interactivity
No `widgetURL`/deep link — tapping should at least open the app; a Lock-Screen/Home "quick add" link to the Add sheet is a cheap win.

---

## 8. Performance

- **P1 🟡** `AddTransactionView` holds `@Query` over *all* transactions sorted by date just to derive known tags + training snapshots — full fetch + sort on every sheet open and every store change while open. Fetch once on appear (or maintain a lightweight distinct-tag store).
- **P3 🟢** `BackupSettingsView.loadTxCounts` does synchronous `Data(contentsOf:)` + full JSON decode per backup file on the main actor.
- **P4 🟢** `ImportPreviewSheet.grouped` re-groups the entire parse result on every render — compute once in `init`/`onAppear`.
- **P2 🟢** `refreshDashboard` snapshots every transaction on each filter change. Fine at current scale (O(n) with detached aggregation); revisit with `FetchDescriptor` predicates if datasets reach 50k+.
- 🟢 `X4`: search matches via `String(Int(tx.amount))` — traps on amounts beyond Int64 / NaN; use `String(format:)` or clamp.

---

## 9. Animation & Polish

- **AN1 🟢** Token adoption is incomplete: `DateRangePicker`, `AppLockView`, `PINSetupSheet`, `AppearanceSettingsView`, onboarding use raw `.easeInOut(duration: 0.2)`/spring literals where `dsEase`/`dsSpring` exist (the DSAnimation header says bespoke AddTransaction/onboarding springs are intentional — the settings/lock literals are not on that list).
- **AN3 🟢** `closeDatePicker()` and the delete flow in `AddTransactionView` chain `DispatchQueue.main.asyncAfter` timings — the same fragile pattern the file's own `ShakeEffect` comment brags about removing. Replace with completion-based animation or `withAnimation` + `transaction`.
- **AN4 🟢** Skeleton rows are static gray — a shimmer (`.redacted` + animated gradient mask) would match the app's polish level.
- **AN2 🟢** Stats always waits a fixed 0.38s before showing charts even when presentation is instant; comments still describe the old *push* presentation though it's now a *sheet* — retune/document.
- 🟢 `X3`: delete-from-edit-sheet dismisses, then deletes 0.3s later; if the delete throws, the error alert is set on an already-dismissed view and never appears.

---

## 10. Code Quality & Architecture

- **A1 🟠 Two parallel Today views.** `TodayView` and `TodayViewV2` (marked "testing") ship behind a user-facing Appearance setting. ~600 lines with duplicated query plumbing, swipe gesture, sheet wiring, scroll content. Every dashboard change must be made twice. Decide on one (or extract the shared scroll content + gesture into one component and keep only the header as the variant).
- **A3 🟡 Duplication hotspots:**
  - `AnkaAutoBackup` payload struct is byte-for-byte identical to `AnkaBackup` — restore even decodes auto-backup files *as* `AnkaBackup`. Delete the private copy.
  - `BackupService.restore` sync + async variants duplicate ~80 lines of merge logic — make sync wrap async (or delete the unused sync one; only `AutoBackupService.restore(file:into:replaceExisting:)` non-progress variant uses it, itself unused by UI).
  - `TxSnap` (Today) ≡ `StatsTxSnap` (Stats); `amountBucket` ×2; month-swipe `DragGesture` ×2; mode-pill UI ×2.
- **A2 🟡 Dead code:** `TransactionFilterEngine` (entire file behind an undefined compile flag), `CategorySlotView` (no references), `AnkaTests.swift` (empty stub), `Font.dsHero`/`dsDisplay`/`dsLargeTitle*` (verify usage), `AppRouter`'s `PeriodFilter.dateInterval` `.month/.custom` fallback branch, `CategoryPredictor.latestPrediction`/`loadModels()` (unused externally).
- **A4 🟢 Stringly-typed keys duplicated:** `"autoBackupLastDate"` literal re-typed in `BackupSettingsView`; `"ankaPINCode"` re-typed inside `AppLockManager.init`; `"anka.appLockEnabled"` likewise; `"ml_corrections"` in two files. Centralize.
- **A7 🟢 Build settings:** deployment target mismatch (app 26.0 vs other targets 26.5); `SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — consider Swift 6 language mode for checked concurrency (codebase is already written for it).
- 🟢 `AutoBackupService.BackupFile.id = UUID()` is regenerated per listing — `txCounts` keyed by it is invalidated on every `loadBackups()` (works only because counts reload right after). Key by filename.

---

## 11. Testing

### X7 🟠 Test suite is effectively absent/broken
- `AddTransactionUITests` references the **old** UI: an "Add" tab (now a toolbar `+`), "Cancel" button (now an ✕), "Add note" placeholder (now "Description"), a custom numpad ("1"–"5" buttons — now a system keyboard), and the **pre-migration** "Food & Dining" category. Every assertion fails on the current app.
- `AnkaTests.swift` is the template stub. The only real coverage is `TransactionParserTests` (good).
- Zero coverage for: CSV parse/escape round-trip, BackupService restore/merge/replace, KeywordMatcher (boundaries/fuzzy), TodayViewModel aggregation (period filters, total-mode netting, day grouping), StatsViewModel (delta %, weekly buckets), migration logic.
**Fix:** delete/rewrite UI tests for the current UI; add unit tests alongside the fixes in this report (each behavioral fix should land with its test).

### 🟢 Localization (U3)
Every string is hardcoded English while the product is deeply Indonesian (IDR, warteg, GoFood…). No String Catalog. Decide: English-only (fine, but adopt `String(localized:)`/catalog now so it's cheap later) or ship `id` localization.

---

# Progress

- ✅ **App Lock tweaks** (done 2026-06-13, post-Batch-11; verified on simulator) — Two user-requested fixes. (1) **PIN-only vs PIN + biometrics:** new persisted `AppLockManager.biometricEnabled` preference + `useBiometrics` (= `canUseBiometrics && biometricEnabled`); `AppLockView` reads `useBiometrics` everywhere and, when off, shows the PIN keypad directly (no biometric button / "Back to Face ID"). Surfaced as a "Use Face ID / Touch ID / Optic ID" toggle in Settings → Security (separate from the now-generic "App Lock" toggle). (2) **Prompt immediately on activation:** enabling the lock (toggle-with-PIN or finishing `PINSetupSheet`) now routes through `SettingsView.engageLock()` → `appLockEnabled = true` + `lock()` + `dismiss()` of the Settings sheet, so the lock screen + biometric prompt appear right away instead of only on the next launch (the overlay sits beneath the sheet, hence the dismiss). Verified end-to-end in the iOS 27 simulator with Face ID enrolled: cold-launch Face ID prompt, matching-face unlock, PIN-only mode showing the keypad directly, and the lock surfacing instantly on enable. 47 tests still green. CONTEXT App Lock section updated.
- ✅ **Batch 1** (done 2026-06-13) — S1 Face ID plist key added; D1 cascade→`.nullify` + affected-count confirmation dialogs in CategoryManagementView & AddEditCategorySheet; D2 auto-backup wired via shared `.autoBackup` modifier on both Today views (foreground 24h gate + throttled after-change) and honest Backup-screen copy; X1 ExportSheet now uses `ShareLink`. Build green.
- ✅ **Batch 2** (done 2026-06-13) — D3 backup payload v2 includes categories (type/emoji/color/order restored, income categories no longer flip to expense); D4 `AppCurrency.code` fallbacks; A3 deleted duplicate `AnkaAutoBackup` struct + dead sync restore path (auto-backups now use `BackupService.export`); A4 `BackupFile` identity = filename, shared `lastBackupKey` constant. Also enabled `ENABLE_TESTABILITY` for Debug + wired `AnkaTests` into the scheme. New `BackupServiceTests` (4 tests) green; full suite passing.
- ✅ **Batch 3** (done 2026-06-13) — Currency strategy: **IDR-only MVP**. D6 locale-aware amount parsing (`AddTransactionViewModel.parseAmount(_:locale:)` + `formattedAmountDisplay` + `TransactionParser.firstNumber` honor `Locale` decimal/grouping separators — "1,5" on id-ID is now 1.5, not 15); D5 parser still strips currency words but foreign codes are no longer persisted (every tx stored as `AppCurrency.code`); D10 `heroAmount` nets income−expense in Total mode under a category filter; X4 non-trapping `%.0f` amount search; U4 added `Double.rupiah`/`signedRupiah` and migrated hardcoded "Rp" sites (AmountLabel, DayHeader, Stats, breakdown, weekly trend, V2 hero). New `AmountParsingTests` (8 tests, id/en locales); 34 tests across 4 suites green.
- ✅ **Batch 11** (done 2026-06-13) — Cleanup pass. **Dead code (A2):** deleted `TransactionFilterEngine.swift` (entire file behind an undefined compile flag) and `CategorySlotView.swift` (never instantiated — only mentioned in comments, now corrected); removed unused `Font.dsHero/dsDisplay/dsLargeTitle/dsLargeTitleBold` tokens and `CategoryPredictor.latestPrediction` + `loadModels()` (incl. their internal assignments). **Duplication (A3):** consolidated the byte-identical `TxSnap` (Today) and `StatsTxSnap` (Stats) into one shared `Models/TransactionSnapshot.swift`. **String keys (A4):** `AppLockManager`'s pin/enabled/grace/lockout keys are now `static let` (init references them instead of re-typing the literals); the duplicated `"ml_corrections"`/`"ml_last_train_count"` literals are centralized in a new `MLStorage` enum used by both predictor and trainer. **Build settings (A7):** aligned all targets' `IPHONEOS_DEPLOYMENT_TARGET` to 26.0 (the documented minimum — project default/tests/widget were 26.5 while the app was 26.0). **Dev tooling (U17):** wrapped the Settings → Developer section in `#if DEBUG` so it can't ship in Release, and unified the `anka.hasCompletedOnboarding` `@AppStorage` default to `false` across `AnkaApp` + `SettingsView`. **Animations (AN1):** replaced raw `.easeInOut(duration: 0.2/0.25)` literals with `.dsEase`/`.dsEaseSlow` tokens in AppLockView, PINSetupSheet, AppearanceSettingsView, DateRangePicker. **AN3 + X3:** AddTransaction's delete now deletes-then-dismisses (was dismiss → `asyncAfter(0.3)` delete, so a thrown error's alert landed on a dismissed view and never showed); `closeDatePicker` drives focus off `withAnimation(completion:)` instead of a hand-tuned `asyncAfter(0.38)`. **AN4:** skeleton rows gained a sweeping shimmer overlay (suppressed under Reduce Motion). Debug + Release build green; 47 tests pass. *Not done (intentional):* `AppRouter`/`PeriodFilter.dateInterval` `.month/.custom` branch kept (required for switch exhaustiveness); `SWIFT_VERSION` left at 5.0 (Swift 6 mode deferred — too risky for a cleanup pass); weak-PIN nudge deferred.
- ✅ **Batch 10** (done 2026-06-13) — Prediction quality. X6: `KeywordMatcher` short keywords (≤5 chars) now match on **word boundaries** (`words.contains`) instead of substrings, killing false positives like "repair"→Home("air"), "premiere"→Eating Out("mie"), "gigantic"→Groceries("giant"), "grabbing"→Taxi("grab"); brand/long keywords keep substring matching ("ke indomaret"→Groceries). P6: correction log capped at the most recent 500 (`CategoryPredictor.maxCorrections`, drops oldest), and `CategoryMLTrainer` now **prunes absorbed entries** after a successful train (removes exactly the corrections folded into the model, preserving any added mid-train) so stale signals stop over-weighting. Shared featurizer: new `MLFeaturizer` enum is the single source of truth for `amountBucket` + the `note+bucket` input string — both predictor (inference) and trainer (training) call it, removing the duplicated logic that could silently drift the model contract. Chip-band decision: the 0.60–0.85 band is formally **folded into auto-assign-with-undo** — `Prediction.shouldShowChip` (dead, no chip UI was ever built) replaced by `shouldSuggest` (≥0.60), which gates `applyMLPrediction`; the existing tappable sparkle pill is the undo affordance. New `KeywordMatcherTests` (8 tests: boundary negatives/positives, brand substrings, bucket tiers/boundaries, featurizer). 47 tests across 7 suites green.
- ✅ **Batch 9** (done 2026-06-13 by user; verified + completed) — Widgets. W1: widget payload now stamped with `snapshotDate`; Home + Lock-screen providers zero stale totals when the stored day ≠ today and add a midnight timeline refresh. W2: lock-screen `indianrupeesign` (₹) replaced with text "Rp". W3: `widgetURL`/`Link` deep links + new `DeepLinkRouter` + `.onOpenURL`; Today views open the Add sheet on `anka://add`. **Verification found two gaps, now fixed:** (a) the `anka://` URL scheme was never registered — added `Anka/Info.plist` with `CFBundleURLTypes` (scheme `anka`), set `INFOPLIST_FILE` on both app configs, and added a synchronized-group membership exception so the plist isn't also copied as a resource (the "Multiple commands produce Info.plist" build error); confirmed the scheme + generated keys merge in the built Info.plist, so `.onOpenURL` now actually fires. (b) X2's central hook was only partial — added a `Notification.Name.ankaDataDidChange` posted after every successful save/delete (AddTransaction), CSV import, and backup restore; both Today views observe it, re-fetch the authoritative transaction list, and rewrite VM + widget data so in-place amount edits and Settings-side import/restore now propagate to the dashboard and widgets. Build green.
- ✅ **Batch 8** (done 2026-06-13) — Category editor. U10: `AddEditCategorySheet` gains a 12-swatch color picker (preset palette on `SettingsViewModel.categoryColorOptions`) so custom categories are no longer all coral `F26666` (which made the donut render identical slices). U11: emoji field validated to a single emoji grapheme — `onChange` keeps only the last grapheme, `SettingsViewModel.isEmojiValid` (accepts single emoji / ZWJ sequences / flags, rejects letters & digits) gates Save with an inline "Pick a single emoji" note. Duplicate-name guard: `isDuplicateName` (case-insensitive, excludes the edited category) blocks Save with an inline note — name uniqueness matters since ML matching is name-based. ML-rename warning: editing one of the 13 ML-coupled default names (`mlLockedNames`) and changing it shows an amber "turns off smart auto-categorization" note (`willBreakMLMatching`). A5: every category `try? modelContext.save()` (add/edit/delete in the sheet + swipe-delete/reorder in `CategoryManagementView`) is now do/catch — failures surface as alerts (`saveErrorMessage` / `SettingsViewModel.categoryErrorMessage`) and keep the sheet open instead of silently dropping edits. Build green.
- ✅ **Batch 7** (done 2026-06-13) — Dynamic Type + VoiceOver. AC1: every remaining fixed-size `DSFont` token (`dsHero`, `dsDisplay`, `dsLargeTitle(+Bold)`, `dsTitle`, `dsTitle2(+Bold)`, `dsTitle3`, `dsHeadline`, `dsSubhead`, `dsBody`, `dsBodyMedium`, `dsCaption`, `dsBadge`) now carries a `relativeTo:` anchor so it scales with Dynamic Type — fixes the core AddTransaction/body/Stats-hero text that didn't scale; corrected the file header's false "all tokens scale" claim. AC2: `CategoryBreakdownRow` collapses to one VoiceOver element reading "Name, Rp amount, NN percent"; `DonutChartView` gains an `.accessibilityRepresentation` exposing one labelled element per category (the gesture-driven slices were invisible to VO). AC3: Today hero is now `.privacySensitive` + `.accessibilityElement` — when hidden it reads "Balance hidden" with no value and exposes the tap as a button with a hide/show/clear-filter hint (VO no longer leaks the blurred amount). AC5: Reduce Motion respected — onboarding `AnkaSparkMark` skips its perpetual spin, AddTransaction suppresses the repeating sparkle pulse and the invalid-save shake (error haptic still fires). AC6: new adaptive `DSColor.accentText` (darkened coral #C4453B in light mode, brand #F26666 in dark) for small coral labels below WCAG AA on white; migrated the caption/footnote coral sites (BackToCurrentMonthChip, Stats reset hint, AppLock PIN links, donut "Set Budget"). Build green.
- ✅ **Batch 6** (done 2026-06-13) — Today month navigation + search UX. U2: new shared `PeriodMenuPill` replaces the old filter-sheet-only period pill — tapping it opens a "Jump to Month" menu (last 12 months, current marked "This Month", + "More Filters…" → existing sheet), giving a discoverable/VoiceOver-reachable alternative to swipe-only month nav; a coral `BackToCurrentMonthChip` appears beside it while browsing a past month/preset (one tap → live month). Both wired into `TodayView` and `TodayViewV2` via new `TodayViewModel` helpers (`jumpToMonth`, `resetToCurrentMonth`, `isViewingCurrentMonth`, `recentMonths`). U5: Stats month label is now a button → `StatsViewModel.resetToCurrentMonth()` (was defined but never called), with a "Tap to return to this month" hint shown when off-month. U6: search now matches `tags` too, and a dedicated search-empty state ("No Results" + "Clear Search") was added to `TransactionEmptyStateView` (distinct from the category-filter "Clear Filters" path), driven by `isSearchActive`/`clearSearch()`. U14 (undo-toast delete) left as the audit's optional item — not implemented this batch. Build green.
- ✅ **Batch 5** (done 2026-06-13) — App-lock hardening. S2: PIN now stored as a per-PIN salted SHA256 credential (`<saltHex>:<hashHex>`, CryptoKit) instead of plaintext, with transparent migration of any legacy plaintext PIN on the next correct entry; keychain items written with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no device migration); escalating, **persisted** brute-force lockout (no penalty <5 misses, then 30s/60s/5m/15m/60m) with a live countdown lockout screen in `AppLockView`. S3: `KeychainHelper.save/delete` now return success; `savePIN`/`removePIN` only flip `hasPIN` on a real write, and `PINSetupSheet` shows an error + stays open if the keychain write fails (no more lock-out-with-no-PIN). S4: lock-grace-period setting (`AppLockManager.GracePeriod`: Immediately/30s/1m/5m) — `enterBackground`/`enterForeground` cover the UI on `.inactive`/`.background` for app-switcher privacy but silently unlock within the grace window, so Control Center / notification pulldowns no longer force re-auth; surfaced as a "Require Unlock" picker in Settings → Security. Build green.
- ✅ **Batch 4** (done 2026-06-13) — D7 full-file RFC-4180 CSV tokenizer `CSVService.parseCSV` (quoted commas/newlines, `""` unescape; note: `\r\n` is one Swift grapheme → matched via `isNewline`); D9 day+amount+type+note duplicate detection in `parsePreview` (existing transactions passed in) with an "Import N duplicates" toggle in `ImportPreviewSheet` (skipped by default); D8 half-open period intervals — `monthInterval` end = `startOfNextMonth`, added `DateInterval.containsHalfOpen` + `Date.addingDays`/`startOfNextMonth`, applied in Today/Stats/Export so boundary transactions land in exactly one period; P4 `ImportPreviewSheet` grouping computed once (state) instead of per-render. New `CSVServiceTests` (6 tests); 40 tests across 5 suites green.

# Action Plan

Grouped into batches sized to be executed **in one prompt each** (shared files, coherent test surface). Order = recommended priority.

| Batch | Theme | Items | Severity |
|---|---|---|---|
| 1 | Crash & data-loss stoppers | S1, D1, D2, X1, U16 | 🔴 |
| 2 | Backup/restore correctness | D3, D4, A3 (backup dedup), BackupFile.id, key constants | 🟠 |
| 3 | Amount & currency correctness | D6, D5, D10, X4, U4 | 🟠 |
| 4 | CSV robustness | D7, D9, D8, P4 | 🟡 |
| 5 | App-lock security hardening | S2, S3, S4 (optional setting) | 🟠 |
| 6 | Today UX: month nav + search | U2, U5 (resetToCurrentMonth), U6, U13, U14 | 🟠 |
| 7 | Dynamic Type & accessibility | AC1, AC2, AC3, AC5, AC6 | 🟠 |
| 8 | Category management UX | U10, U11, duplicate-name guard, ML-rename warning, A5 error surfacing | 🟡 |
| 9 | Widgets | W1, W2, W3, X2 (central post-save hook) | 🟡 |
| 10 | Prediction quality | X6, P6, chip-band decision, shared amountBucket | 🟡 |
| 11 | Code-quality cleanup | A2, A3 (rest), A4, A7, U17, AN1, AN3, AN4, X3 | 🟢 |
| 12 | Test suite rebuild | X7 (UI tests rewrite + unit tests for batches 2–4, 10) | 🟠 |
| 13 | Today view consolidation | A1 (needs your V1-vs-V2 decision first) | 🟠 |
| 14 | Pre-launch product | U1 (icon), U7/U8 (StoreKit or strip), U15 (iPad decision), U3 (localization decision), legal links | 🔴 for launch |

## Batch details (what each prompt should say)

**Batch 1 — "Fix the critical crash/data-loss items from AUDIT.md batch 1"**
1. Add `INFOPLIST_KEY_NSFaceIDUsageDescription` ("Anka uses Face ID to unlock the app.") to both app configs.
2. `Category.transactions` delete rule → `.nullify`; add confirmation dialogs in `CategoryManagementView` + `AddEditCategorySheet` showing affected transaction count.
3. Wire auto-backup: post-save/delete trigger + foreground `shouldBackup()` gate; fix the "Status: Enabled" copy.
4. Replace `ExportSheet`'s `UIActivityViewController` with `ShareLink`.

**Batch 2 — "Backup v2"**
Categories in payload (version 2 + backward-compatible decode), `AppCurrency.code` fallbacks, delete `AnkaAutoBackup` duplicate struct, sync-restore wraps async, `BackupFile` identity by filename, extract `autoBackupLastDate` constant. Unit tests: v1→v2 restore, merge vs replace, category-type preservation.

**Batch 3 — "Amount & currency correctness"**
Locale-aware decimal parsing in `AddTransactionViewModel` + `TransactionParser`; pick currency strategy (recommend IDR-only for MVP: parser returns IDR, stop persisting parsed foreign codes, keep schema field); fix Total-mode filtered netting; safe amount→string in search; single currency-format helper replacing hardcoded "Rp". Tests for `1,5` / `1.5` / `1.500` in id/en locales.

**Batch 4 — "CSV robustness"**
State-machine CSV parser (quotes/newlines/unescape) + round-trip tests; duplicate detection in preview; half-open date intervals replacing `-1 second` endings; memoize `ImportPreviewSheet.grouped`.

**Batch 5 — "App-lock hardening"**
Hash PIN (salted SHA256) with migration from plaintext; `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; KeychainHelper returns success; escalating lockout (persisted attempt counter); optional lock-grace-period setting.

**Batch 6 — "Today month navigation + search UX"**
Month menu on period pill / month label tap; "back to current month" chip; Stats month-label tap → `resetToCurrentMonth()`; search-aware empty state + clear-search; tags in search; undo-toast delete (optional).

**Batch 7 — "Dynamic Type + VoiceOver"**
`relativeTo:` on all remaining DSFont tokens (fix the file's header claim); donut accessibility elements; hidden-balance `privacySensitive` + labels; Reduce Motion variants for onboarding/sparkle/shake; coral small-text contrast audit.

**Batch 8 — "Category editor"**
Color palette picker, emoji validation (single grapheme, emoji presentation), duplicate-name guard, warning when renaming ML-coupled default names, surface `context.save()` errors.

**Batch 9 — "Widgets"**
Dated widget payload + midnight zeroing + midnight timeline entry; replace `indianrupeesign`; `widgetURL` deep links (open app / quick-add); central "data changed" hook that feeds VM + `WidgetDataWriter` after save/delete/import/restore (also resolves X2).

**Batch 10 — "Prediction quality"**
Word-boundary matching for short keywords (+ tests with "repair", "premiere", "theory"); cap corrections log; shared `amountBucket`; decide chip UI vs fold band.

**Batch 11 — "Cleanup pass"**
Delete dead code (TransactionFilterEngine, CategorySlotView, stale font tokens, unused predictor API); consolidate TxSnap/StatsTxSnap + swipe gesture + mode pills; centralize string keys; align deployment targets; `#if DEBUG` developer section; unify `hasCompletedOnboarding` default; adopt animation tokens in settings/lock/date-picker; fix delete-error-after-dismiss (X3); replace asyncAfter chains.

**Batch 12 — "Tests"**
Rewrite `AddTransactionUITests` against current UI; add launch/smoke UI test; unit tests for TodayViewModel (periods, grouping, daily totals), StatsViewModel (delta, weekly buckets), KeywordMatcher, migration.

**Batch 13 — "One Today view"** *(after you choose V1 or V2)*
Remove the loser + the Appearance toggle, extract shared scroll content so the remaining file is single-source.

**Batch 14 — "Launch readiness"**
App icon assets; StoreKit 2 paywall (or strip placeholders); iPhone-only vs iPad decision; String Catalog adoption (en, optionally id); real Terms/Privacy links.
