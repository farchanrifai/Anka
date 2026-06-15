# Anka Liquid Glass Audit

Date: 2026-06-16  
Scope: Native iOS 26 feel across Liquid Glass surfaces, shell chrome, transitions, and motion.  
Goal: Judge both API correctness and whether the app actually feels like a system-quality iOS app.

## Executive Summary

Anka already uses the real iOS 26 Liquid Glass APIs in the right high-value place: the inline composer. The app also uses zoom transitions and restrained dark surfaces well enough that it often gestures toward Apple-native UI. The main gap is coherence. Liquid Glass is currently a **local feature treatment**, not a **shell-wide interaction language**. Nearby controls fall back to plain fills, `Material`, or standard bordered buttons, so the app feels partly native and partly custom.

This is not a "rewrite the design system" problem. It is mostly a consistency, motion, and chrome-vocabulary problem. The highest-value follow-up work is to make the Today shell, composer/edit flows, and sheet chrome agree on one native interaction language.

## Health Score

| Area | Score | Notes |
|---|---:|---|
| Liquid Glass API correctness | 3/4 | Real APIs are used correctly in the composer/edit flows, but not applied consistently enough across adjacent surfaces. |
| Native shell feel | 2/4 | Zoom transitions and hidden bars help, but the shell lacks one coherent glass/chrome vocabulary. |
| Composer/edit coherence | 2/4 | Strong start in V3 composer, weaker consistency once editing/saving/deleting enters the flow. |
| Motion and morphing fit | 2/4 | Some transitions feel native; timing glue and fixed delays still weaken the illusion. |
| **Total** | **9/16** | **Good foundation, incomplete native-system finish** |

## What Is Already Working

- The inline composer uses `GlassEffectContainer`, `glassEffect`, and `glassEffectID` intentionally, with a clear separation between the summary bubble namespace and the row namespace. See [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:1).
- Interactive glass is mostly used on interactive surfaces, especially the category bubble and armed send button in the inline composer.
- Zoom-source wiring is thoughtful and consistent across Add / Stats / Filter / row edit entry points. See [`TodayToolbarButtons.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/TodayToolbarButtons.swift:1), [`TodaySheets.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/TodaySheets.swift:1), and [`TransactionRow.swift`](/Users/farchan/Xcode/Anka/Anka/Components/TransactionRow.swift:1).
- The app avoids fake glassmorphism CSS-style tricks and uses native SwiftUI/iOS 26 primitives instead of custom blur stacks.

## Batch 1 — Glass API Correctness And Consistency

### P1 Mixed material vocabulary breaks the "system" illusion
- Evidence:
  - True Liquid Glass in [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:60)
  - True Liquid Glass in [`EditTransactionSheet.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/EditTransactionSheet.swift:33)
  - `ultraThinMaterial` day chips in [`DayHeaderView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/DayHeaderView.swift:1)
  - `regularMaterial` sheet background in [`CategoryFilterSheet.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/CategoryFilterSheet.swift:53)
  - plain `borderedProminent` Add button in [`TodayToolbarButtons.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/TodayToolbarButtons.swift:45)
- Impact: the user moves between "real glass", "UIKit-ish material", and "plain SwiftUI button" within the same task flow. That reads as custom app styling, not native shell continuity.
- Fix direction: define a minimal glass vocabulary for shell-adjacent controls and sheet chrome. Not every control must become glass, but each control family should have a deliberate rule.

### P2 Modifier usage is mostly correct, but duplicated and easy to drift
- Evidence: repeated `glassEffect(..., in: .capsule/.circle)` patterns in composer and edit sheet.
- Impact: correctness is currently manual. Small divergence later will make similar controls feel unrelated.
- Fix direction: add a tiny internal helper layer only for repeated transactional control treatments, not a new design system.

### P3 No issue: missing `#available(iOS 26, *)`
- This is intentionally **not** a defect because the app minimum is iOS 26+.

## Batch 2 — Native Shell And Chrome Audit

### P1 The shell does not yet have one coherent control vocabulary
- Evidence:
  - Today shell uses standard toolbar buttons and a prominent bordered Add button in [`TodayToolbarButtons.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/TodayToolbarButtons.swift:1)
  - Settings and Highlights close affordances are plain icon buttons in [`SettingsView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Settings/SettingsView.swift:1) and [`HighlightsView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Highlights/HighlightsView.swift:1)
  - Filter sheet uses `presentationBackground(.regularMaterial)` while the composer/edit flow uses true glass
- Impact: the app relies on hidden bars and zoom transitions to feel native, but the top-level chrome itself still feels mixed.
- Fix direction: decide which shell controls should stay intentionally plain and which should join a glass-forward vocabulary. Document that rule and apply it consistently across Today, Stats, Highlights, Settings, and the filter sheet.

### P2 Sticky day headers feel adjacent to glass, not part of the same system
- Evidence: [`DayHeaderView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/DayHeaderView.swift:1) uses `ultraThinMaterial` capsules that visually suggest glass without actually participating in the same liquid behavior.
- Impact: these chips can feel like "close enough" custom material, which lowers the premium/native feel during scrolling.
- Fix direction: either make them intentionally plain tonal chips or pull them into the same glass/material language as the shell. Right now they sit awkwardly in between.

### P2 Sheet backgrounds are inconsistent with the rest of the shell
- Evidence:
  - Filter sheet: `presentationBackground(.regularMaterial)`
  - Category picker: solid background in [`CategoryPickerSheet.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/CategoryPickerSheet.swift:1)
  - Edit sheet: no explicit shell-level background policy, only glass child controls
- Impact: system apps tend to make sheet identity feel deliberate. These current surfaces feel assembled case-by-case.
- Fix direction: standardize sheet background treatment by sheet type: utility filter sheet, editor sheet, full-screen add flow.

## Batch 3 — Composer And Edit-Flow Coherence

### P1 V3 composer and V3 edit sheet do not fully agree on action treatment
- Evidence:
  - Composer send button is a glass circle with accent tint in [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:190)
  - Edit save button is a plain filled capsule in [`EditTransactionSheet.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Today/Shared/EditTransactionSheet.swift:207)
  - Delete is glass in edit, but save is not
- Impact: the "same subsystem" changes character between create and edit. That makes V3 feel like two separate experiments rather than one native pattern.
- Fix direction: define one transactional vocabulary:
  - circle action for compact auxiliary actions
  - capsule field for editable inputs
  - prominent confirmation treatment for commit/save/send
  - destructive treatment that still belongs to the same family

### P2 Composer is the strongest native surface; neighboring flows drag it down
- Evidence:
  - Composer host behavior in [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:220)
  - Add flow still uses a more custom full-screen structure in [`AddTransactionView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/AddTransactionView.swift:1)
- Impact: the app’s most Apple-native surface is not yet the dominant pattern in the surrounding transaction flow.
- Fix direction: future implementation should either elevate V3 as the canonical pattern or align V1/V1-edit surfaces more closely with it.

## Batch 4 — Motion, Morphing, And Performance Fit

### P1 Delay-based motion still weakens the native feel
- Evidence:
  - `DispatchQueue.main.asyncAfter` in composer reveal path in [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:1)
  - `DispatchQueue.main.asyncAfter` in lock view focus/error handling in [`AppLockView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AppLock/AppLockView.swift:1)
  - fixed chart delay in [`StatsView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/Stats/StatsView.swift:1)
  - more timing choreography in [`AddTransactionView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/AddTransactionView.swift:1)
- Impact: system-native motion tends to feel state-driven and resilient. Timed sleeps and post-animation delays make the UI feel handcrafted in a fragile way, especially around focus and presentation.
- Fix direction: replace fixed waits with state completion, presentation lifecycle, or view-identity-driven transitions wherever possible.

### P2 Good morphing exists, but surface continuity is incomplete
- Evidence:
  - Strong source/destination zoom links in Today shell and row editing
  - Composer summary bubble carefully separated into its own namespace
- Impact: some transitions are excellent in isolation, but the destination surfaces do not always visually justify the zoom source. The motion is stronger than the shell vocabulary it lands in.
- Fix direction: pair zoom transitions with more consistent destination chrome so the arriving surface feels like the natural expanded form of the source control.

### P2 Open/close motion semantics are not yet system-consistent
- Evidence: composer uses asymmetric open/close rules in [`InlineTransactionEntryView.swift`](/Users/farchan/Xcode/Anka/Anka/Views/AddTransaction/InlineTransactionEntryView.swift:220), while other sheets rely on standard sheet behavior and some custom timing.
- Impact: each flow feels individually tuned rather than governed by one system rhythm.
- Fix direction: define a small set of native motion rules for:
  - toolbar button to sheet
  - row to editor
  - inline composer open/close
  - dismiss back to source

## Recommended Implementation Order

1. **Batch 3 first** — strongest user-facing gain with limited surface area: make composer and edit flows share one vocabulary.
2. **Batch 2 second** — bring shell chrome into agreement with the transactional subsystem.
3. **Batch 4 third** — remove timing glue and retune transitions once the visual destinations are coherent.
4. **Batch 1 as a cleanup rail across all batches** — use it as the correctness checklist while implementing the other three.

## Acceptance Criteria For Later Fixes

- Shell controls share one deliberate material vocabulary instead of mixing glass, generic material, and default SwiftUI styling case-by-case.
- Transaction create/edit/delete flows feel like one subsystem, not separate experiments.
- Glass is used where it improves native affordance, not merely as decoration.
- Core transitions are state-driven and resilient; no fragile delays are required for normal presentation/focus flows.
- The app feels closer to Messages / Mail / Wallet in interaction quality, not just in color palette and hidden bars.

## Verification Checklist

When implementing the fixes later, verify on simulator or device:

- Composer open/close with keyboard already visible and from a cold open
- Add / Stats / Filter zoom source quality and destination continuity
- V3 edit sheet appearance, save, delete, and dismissal
- Sticky day headers while scrolling over real data
- Search activation while the bottom bar is visible, hidden, and restored
- Reduce Motion behavior on glass-adjacent transitions
- Re-entry after dismissing sheets back into the originating control

