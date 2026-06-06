# Anka — Claude Code Project Context

> Read this file at the start of every Claude Code session before doing anything.
> Update the Phase Status section after each completed phase.

---

## App Identity

- **Name:** Anka
- **Platform:** iOS only (no macOS, no Android)
- **Minimum iOS:** 26.0 (uses Liquid Glass tab bar APIs: `role: .search` detached Add button, `.tabBarMinimizeBehavior`)
- **Bundle ID:** com.nc.anka
- **App Group:** group.com.nc.anka
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
transactions: [Transaction] // @Relationship(deleteRule: .nullify)
```

---

## App Navigation

**Liquid Glass tab bar (iOS 26):**
- Left pill/island: **Today** (dashboard + transaction list) + **Reports** (monthly summary, charts) grouped together
- Right detached button: **Add** — `role: .search` detaches it from the pill; intercepted via `onChange` (opens sheet, restores previous tab, does NOT navigate)
- `.tabBarMinimizeBehavior(.onScrollDown)` — bar minimizes as content scrolls down

**Settings:** accessible from Today tab via gear icon (top-right)

**Add Transaction flow:** full-screen modal → numpad → category row → optional note → Save

---

## MVP Features (Phase 0–9)

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
│   ├── Reports/
│   │   ├── ReportsView.swift
│   │   └── ReportsViewModel.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── CategoryManagementView.swift
├── Components/               // reusable UI, no business logic
│   ├── TransactionRow.swift
│   ├── AmountLabel.swift
│   └── SectionHeader.swift
├── Services/
│   ├── CategoryPredictor.swift    // ported from Spendy
│   ├── CategoryMLTrainer.swift    // ported from Spendy
│   ├── KeywordMatcher.swift       // ported from Spendy
│   ├── TransactionFilterEngine.swift // ported from Spendy
│   ├── AppLockManager.swift       // ported from Spendy
│   └── WidgetDataWriter.swift     // rewritten clean
└── Resources/
    ├── Assets.xcassets
    └── StarterCategoryClassifier.mlmodelc  // ported from Spendy
```

---

## Files Ported from Spendy

Copy these verbatim from the Spendy project — do not rewrite:
- `CategoryPredictor.swift` → update App Group ID to `group.com.nc.anka`
- `CategoryMLTrainer.swift` → update App Group ID
- `KeywordMatcher.swift` → no changes needed
- `TransactionFilterEngine.swift` → no changes needed
- `AppLockManager.swift` → update Keychain key to `"ankaPINCode"`
- `DSFont.swift` → clean up tokens to 8–10 only
- `StarterCategoryClassifier.mlmodelc` → drag into Resources/

Do NOT port: any View files, FirestoreSyncService, ProfileManager, InsightEngine, RecurringDetector, BackupService, CSVService, DashboardV2/V3.

---

## Phase Status

| Phase | Name | Status |
|---|---|---|
| 0 | Project Setup + Design System | ✅ Done |
| 1 | Data Models | ⬜ Not started |
| 2 | Add Transaction | ⬜ Not started |
| 3 | Today View | ⬜ Not started |
| 4 | Reports View | ⬜ Not started |
| 5 | Settings + Categories | ⬜ Not started |
| 6 | ML Auto-Categorization | ⬜ Not started |
| 7 | Widgets | ⬜ Not started |
| 8 | App Lock | ⬜ Not started |
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
