# Phase 8.7: Highlights Page (Apple Health-Inspired)

## Objective
Build a standalone **Highlights** page for Anka that replicates the Apple Health "Highlights" UI — exact layout and chart style — but for expenses, themed to Anka's dark palette. Three cards: Daily, Weekly, Monthly. Charts built with **Swift Charts** (native).

This **complements** the existing Stats sheet (do not remove Stats). Accessed via a "Highlights" text link under the hero total on the main view.

---

## Design System (CRITICAL — Anka Dark Theme)

The Apple Health reference is light mode. Anka is dark. Replicate the **layout and chart style**, but apply Anka tokens:

- **Page background:** `DSColor.background` (`#0E0E0E`)
- **Card surface:** `DSColor.cardSurface` (`#1A1A1A`), rounded `DSRadius.large`
- **Accent / "Today" / highlight:** `DSColor.accent` (coral `#F26666`) — this is Health's "orange" equivalent
- **"Average" / comparison:** secondary gray (`Color.gray` or `DSColor.textSecondary`)
- **Primary text:** white / `DSColor.text`
- **Section headers** ("Daily Highlights", etc.): large bold, `DSFont` title weight
- **Card label** (🔥 Steps equivalent): use a coin/wallet emoji + "Spending" in coral, small
- **Descriptive sentence:** `DSFont.body`, white
- **Divider** under sentence: thin gray line
- NO hardcoded hex, font sizes, or radii — use design tokens only

**Card anatomy (matches Health):**
```
┌─────────────────────────────┐
│ 💰 Spending                  │  ← coral label, small
│                              │
│ [Descriptive sentence]       │  ← body, white
│ ─────────────────────────    │  ← divider
│                              │
│ [Chart / stat block]         │
└─────────────────────────────┘
```

---

## PHASE A — Navigation + Insight Engine + Weekly Card

### A1. Add Highlights Entry Point
**File:** `Views/Today/TodayView.swift` (modify)

Below the hero total number (the big `Rp 154,040`), add a tappable text link:

```swift
NavigationLink(destination: HighlightsView()) {
    HStack(spacing: 4) {
        Text("Highlights")
            .font(DSFont.body)
            .foregroundColor(DSColor.accent)
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(DSColor.accent)
    }
}
.padding(.top, DSSpacing.small)
```

Place it directly under the total, left-aligned. Do NOT disturb existing layout above/below.

### A2. Create Insight Engine
**File:** `Services/HighlightInsightEngine.swift` (new)

Rule-based engine. No AI/network. Computes all numbers + generates copy.

```swift
import Foundation

enum HighlightPeriod { case daily, weekly, monthly }

enum Trend { case up, down, stable }

struct CategoryHighlight {
    let category: Category
    let amount: Double
    let percentOfTotal: Double
    let deltaVsAverage: Double  // e.g. +0.48 = 48% higher than its own trailing avg
    let isAnomaly: Bool         // true if |deltaVsAverage| > anomalyThreshold
}

struct WeeklyHighlightData {
    let dailyTotals: [Double]       // 7 values, oldest→newest (S..S order to match Health)
    let dayLabels: [String]         // ["S","M","T","W","T","F","S"]
    let dailyAverage: Double        // the orange RuleMark value
    let descriptiveText: String     // "You averaged Rp 225,000 a day over the last 7 days."
    let topCategory: CategoryHighlight?
}

struct MonthlyHighlightData {
    let thisMonthAvgPerDay: Double
    let lastMonthAvgPerDay: Double
    let thisMonthLabel: String      // "June"
    let lastMonthLabel: String      // "May"
    let trend: Trend
    let descriptiveText: String     // "This month, you're spending less per day than last month."
    let topCategory: CategoryHighlight?
}

struct DailyHighlightData {
    let todayTotal: Double
    let averageTotal: Double         // typical daily total (trailing 30d, excl today)
    let cumulativeToday: [(time: Date, amount: Double)]    // cumulative spend points today
    let cumulativeAverage: [(time: Date, amount: Double)]  // typical cumulative-by-time curve
    let currentTimeMarker: Date
    let descriptiveText: String      // "You're spending less than you usually do by this point."
    let hasEnoughDataForChart: Bool  // false → daily card falls back to dual-stat only
}

@MainActor
final class HighlightInsightEngine {
    private let modelContext: ModelContext
    private let calendar = Calendar.current
    private let anomalyThreshold = 0.40   // 40%
    private let lookbackDays = 30

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func weeklyHighlight(currency: String) -> WeeklyHighlightData { /* ... */ }
    func monthlyHighlight(currency: String) -> MonthlyHighlightData { /* ... */ }
    func dailyHighlight(currency: String) -> DailyHighlightData { /* ... */ }
}
```

**Computation rules:**

**Weekly:**
- `dailyTotals`: sum expenses for each of the last 7 calendar days, ordered to match weekday labels
- `dailyAverage`: mean of the 7 daily totals
- `descriptiveText`: "You averaged {formatted avg} a day over the last 7 days."
- `topCategory`: category with highest spend this week + its % of weekly total

**Monthly:**
- `thisMonthAvgPerDay`: this-calendar-month total ÷ days elapsed so far
- `lastMonthAvgPerDay`: last-calendar-month total ÷ days in that month
- `trend`: compare the two
- `descriptiveText`:
  - up → "This month, you're spending more per day than last month."
  - down → "This month, you're spending less per day than last month."
  - stable → "Your daily spending is about the same as last month."

**Daily:**
- `todayTotal`: sum of today's expenses
- `averageTotal`: mean daily total over trailing 30 days, excluding today
- `cumulativeToday`: running cumulative sum of today's transactions ordered by `createdAt`
- `cumulativeAverage`: typical cumulative-by-time curve — for each transaction time bucket, average cumulative spend at that time across the lookback window (approximate; bucket by hour)
- `currentTimeMarker`: `Date()` now
- `hasEnoughDataForChart`: `true` if today has ≥ 2 transactions AND lookback has usable data; else `false`
- `descriptiveText`:
  - todayTotal < averageTotal*0.7 → "You're spending less than you usually do by this point."
  - todayTotal > averageTotal*1.3 → "You're spending more than you usually do by this point."
  - else → "Your spending today is on track."

**Anomaly detection (all periods):**
- For top category, compute its spend this period vs its trailing-period average
- `isAnomaly = abs(deltaVsAverage) > anomalyThreshold`
- If anomaly, the card can append: "{Category} is {±X}% vs usual."

### A3. Create Highlights Page Shell + Weekly Card
**Files:**
- `Views/Highlights/HighlightsView.swift` (new)
- `Views/Highlights/WeeklyHighlightCard.swift` (new)

**HighlightsView:**
```swift
struct HighlightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine: HighlightInsightEngine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                // Phase A: Weekly only. Phases B/C add Monthly + Daily above/below.
                sectionHeader("Weekly Highlights")
                if let engine {
                    WeeklyHighlightCard(data: engine.weeklyHighlight(currency: currencyCode))
                }
            }
            .padding(DSSpacing.screenEdge)
        }
        .background(DSColor.background)
        .navigationTitle("Highlights")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if engine == nil { engine = HighlightInsightEngine(modelContext: modelContext) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DSFont.titleBold)   // large bold
            .foregroundColor(DSColor.text)
    }
}
```

**WeeklyHighlightCard** — exact Health weekly replica using Swift Charts:
```swift
import Charts

struct WeeklyHighlightCard: View {
    let data: WeeklyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            // Card label
            Text("💰 Spending")
                .font(DSFont.caption)
                .foregroundColor(DSColor.accent)

            // Descriptive sentence
            Text(data.descriptiveText)
                .font(DSFont.body)
                .foregroundColor(DSColor.text)

            Divider().background(Color.gray.opacity(0.3))

            // "Average Spend" label + big number
            VStack(alignment: .leading, spacing: 2) {
                Text("Average Spend")
                    .font(DSFont.caption)
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCurrency(data.dailyAverage))
                        .font(DSFont.largeNumber)
                        .foregroundColor(DSColor.text)
                }
            }

            // Bar chart with average rule line
            Chart {
                ForEach(Array(data.dailyTotals.enumerated()), id: \.offset) { idx, value in
                    BarMark(
                        x: .value("Day", data.dayLabels[idx]),
                        y: .value("Spend", value)
                    )
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .cornerRadius(DSRadius.small)
                }
                RuleMark(y: .value("Average", data.dailyAverage))
                    .foregroundStyle(DSColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .frame(height: 180)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(DSSpacing.medium)
        .background(DSColor.cardSurface)
        .cornerRadius(DSRadius.large)
    }
}
```

**Phase A deliverables:** navigation link, insight engine (all 3 methods stubbed/implemented), Highlights page rendering Weekly card. Verify weekly numbers and bar chart match real data.

---

## PHASE B — Monthly Card

**File:** `Views/Highlights/MonthlyHighlightCard.swift` (new)
**Modify:** `Views/Highlights/HighlightsView.swift` — add Monthly section below Weekly.

Exact Health monthly replica: two **horizontal comparison bars** (this month coral, last month gray), each with big number + "/day" suffix + month label.

```swift
struct MonthlyHighlightCard: View {
    let data: MonthlyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            Text("💰 Spending")
                .font(DSFont.caption)
                .foregroundColor(DSColor.accent)

            Text(data.descriptiveText)
                .font(DSFont.body)
                .foregroundColor(DSColor.text)

            Divider().background(Color.gray.opacity(0.3))

            // This month bar (coral)
            comparisonRow(
                amount: data.thisMonthAvgPerDay,
                label: data.thisMonthLabel,
                color: DSColor.accent,
                maxAmount: max(data.thisMonthAvgPerDay, data.lastMonthAvgPerDay)
            )

            // Last month bar (gray)
            comparisonRow(
                amount: data.lastMonthAvgPerDay,
                label: data.lastMonthLabel,
                color: Color.gray.opacity(0.4),
                maxAmount: max(data.thisMonthAvgPerDay, data.lastMonthAvgPerDay)
            )
        }
        .padding(DSSpacing.medium)
        .background(DSColor.cardSurface)
        .cornerRadius(DSRadius.large)
    }

    private func comparisonRow(amount: Double, label: String, color: Color, maxAmount: Double) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.small) {
            // Big number + /day suffix
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatCurrency(amount))
                    .font(DSFont.largeNumber)
                    .foregroundColor(DSColor.text)
                Text("/day")
                    .font(DSFont.caption)
                    .foregroundColor(.gray)
            }
            // Proportional horizontal bar with month label inside
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * CGFloat(amount / maxAmount), 60))
                    Text(label)
                        .font(DSFont.caption)
                        .foregroundColor(color == DSColor.accent ? .white : DSColor.text)
                        .padding(.leading, DSSpacing.medium)
                }
            }
            .frame(height: 44)
        }
    }
}
```

**Phase B deliverables:** Monthly card with two proportional horizontal bars. Verify avg/day math and bar proportions.

---

## PHASE C — Daily Card (cumulative line + dual stat)

**File:** `Views/Highlights/DailyHighlightCard.swift` (new)
**Modify:** `Views/Highlights/HighlightsView.swift` — add Daily section ABOVE Weekly (matches Health order: Daily → Weekly → Monthly).

Exact Health daily replica: dual stat (Today coral / Average gray) + cumulative line chart (today vs typical) with a vertical "now" marker. Falls back to dual-stat-only when `hasEnoughDataForChart == false`.

```swift
import Charts

struct DailyHighlightCard: View {
    let data: DailyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            Text("💰 Spending")
                .font(DSFont.caption)
                .foregroundColor(DSColor.accent)

            Text(data.descriptiveText)
                .font(DSFont.body)
                .foregroundColor(DSColor.text)

            Divider().background(Color.gray.opacity(0.3))

            // Dual stat: Today vs Average
            HStack(spacing: DSSpacing.large) {
                statColumn(dot: DSColor.accent, label: "Today",
                           amount: data.todayTotal, color: DSColor.accent)
                statColumn(dot: .gray, label: "Average",
                           amount: data.averageTotal, color: .gray)
            }

            // Cumulative line chart (only if enough data)
            if data.hasEnoughDataForChart {
                Chart {
                    ForEach(data.cumulativeAverage, id: \.time) { pt in
                        LineMark(x: .value("Time", pt.time),
                                 y: .value("Cumulative", pt.amount),
                                 series: .value("Series", "Average"))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(data.cumulativeToday, id: \.time) { pt in
                        LineMark(x: .value("Time", pt.time),
                                 y: .value("Cumulative", pt.amount),
                                 series: .value("Series", "Today"))
                        .foregroundStyle(DSColor.accent)
                        .interpolationMethod(.stepEnd)
                    }
                    RuleMark(x: .value("Now", data.currentTimeMarker))
                        .foregroundStyle(Color.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .frame(height: 180)
                .chartYAxis(.hidden)
            }
        }
        .padding(DSSpacing.medium)
        .background(DSColor.cardSurface)
        .cornerRadius(DSRadius.large)
    }

    private func statColumn(dot: Color, label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(label).font(DSFont.caption).foregroundColor(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatCurrency(amount))
                    .font(DSFont.largeNumber)
                    .foregroundColor(color)
            }
        }
    }
}
```

**Daily chart note:** expenses are spiky, so use `.interpolationMethod(.stepEnd)` (stair-step), NOT smooth curves — this is correct and honest for transaction data. If `hasEnoughDataForChart` is false, show only the dual-stat block.

**Phase C deliverables:** Daily card with dual stat + cumulative stair-step chart + now marker, with graceful fallback. Final card order in HighlightsView: Daily → Weekly → Monthly.

---

## Files Summary

**New:**
- `Services/HighlightInsightEngine.swift` (Phase A)
- `Views/Highlights/HighlightsView.swift` (Phase A, extended in B & C)
- `Views/Highlights/WeeklyHighlightCard.swift` (Phase A)
- `Views/Highlights/MonthlyHighlightCard.swift` (Phase B)
- `Views/Highlights/DailyHighlightCard.swift` (Phase C)

**Modify:**
- `Views/Today/TodayView.swift` — add Highlights navigation link (Phase A)

---

## Constraints & Notes

- **Swift Charts only** (native, iOS 16+). Do NOT use any web/JS charting.
- **Reuse** existing currency formatter (`formatCurrency` / centralized currency code) — do not reinvent.
- **Reuse** existing `Category` model and expense query patterns.
- Engine is **rule-based, on-device, offline** — no AI/network calls.
- Respect all design tokens; no hardcoded hex/sizes/radii.
- Highlights page is **independent** of the main view's selected period — always shows daily/weekly/monthly relative to today.
- Do NOT remove or modify the existing **Stats** sheet — Highlights complements it.
- If `DSFont.largeNumber` / `DSFont.titleBold` tokens don't exist, add them to the design system file rather than hardcoding.

---

## Testing Checklist

**Phase A:**
- [ ] "Highlights" link appears under hero total, pushes full page
- [ ] Weekly card: 7 bars match last-7-days spend, coral avg line correct
- [ ] "Average Spend" number = mean of 7 days
- [ ] Descriptive sentence reads naturally with real numbers

**Phase B:**
- [ ] Monthly card: two horizontal bars, proportional widths correct
- [ ] avg/day = month total ÷ days elapsed (this) / days in month (last)
- [ ] Trend sentence matches direction

**Phase C:**
- [ ] Daily card: Today (coral) vs Average (gray) numbers correct
- [ ] Cumulative chart stair-steps, today vs typical, now-marker at current time
- [ ] Fallback to dual-stat when today has < 2 transactions
- [ ] Card order: Daily → Weekly → Monthly

**All:**
- [ ] Dark theme consistent (cards `#1A1A1A`, bg `#0E0E0E`, coral accent)
- [ ] No layout break on small devices
- [ ] Empty state handled (no transactions → friendly placeholder, not crash)
