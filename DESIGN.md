---
name: Anka
description: A personal expense tracker, dark and glass-native, with one coral signal
colors:
  coral-accent: "#F26666"
  coral-accent-text-light: "#C4453B"
  positive-green: "#34C759"
  bg-primary: "#0E0E0E"
  bg-card: "#1A1A1A"
  bg-secondary: "#222222"
typography:
  display:
    fontFamily: "SF Pro (system), -apple-system, sans-serif"
    fontSize: "52px"
    fontWeight: 900
    lineHeight: 1
  title:
    fontFamily: "SF Pro (system)"
    fontSize: "34px"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro (system)"
    fontSize: "20px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system)"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.3
  label:
    fontFamily: "SF Pro (system)"
    fontSize: "13px"
    fontWeight: 400
rounded:
  small: "8px"
  medium: "14px"
  large: "20px"
  full: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
  xxxl: "48px"
  screenEdge: "20px"
components:
  card:
    backgroundColor: "{colors.bg-card}"
    rounded: "{rounded.large}"
    padding: "{spacing.md}"
  button-primary:
    backgroundColor: "{colors.coral-accent}"
    textColor: "#FFFFFF"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  toolbar-button:
    backgroundColor: "{colors.bg-secondary}"
    rounded: "{rounded.full}"
    size: "44px"
    height: "44px"
    width: "44px"
---

# Design System: Anka

## 1. Overview

**Creative North Star: "The Native Glass"**

Anka is a personal expense tracker that should feel like it shipped inside
iOS 26, not bolted onto it. The system leans into Liquid Glass: toolbar
controls, the inline composer, and sheet chrome are translucent materials
that float over a near-black canvas, picking up depth from blur and light
rather than drawn shadows. Against that quiet, neutral base, a single coral
accent (#F26666) marks the one thing on screen worth noticing — a CTA, an
expense amount, a selected state.

This system explicitly rejects the "fintech SaaS dashboard" look: no
gradient hero cards, no dense data tables, no side-stripe accent borders, no
identical stat-card grids, no tiny uppercase eyebrow labels. Apple Health,
Wallet, and Reminders are the reference points — spare layouts, generous
whitespace, native components (`List`, `NavigationStack`, `.glassEffect`)
over custom chrome.

**Key Characteristics:**
- Dark-first, near-black canvas with tonal surface steps (no shadows)
- Liquid Glass materials carry depth and interactivity (toolbars, composer, sheets)
- One coral accent, used sparingly and deliberately
- SF Pro throughout, Dynamic-Type-scaled via UIFontMetrics
- Native iOS components first; custom chrome only where Apple's own apps would have it

## 2. Colors

A near-black neutral base with tonal surface steps, one coral accent, and a
single semantic green for income.

### Primary
- **Coral Signal** (`#F26666`): the one accent. Marks the primary action
  (Save, Add button), expense amounts, selected filter/category states, and
  the "Highlights" link. Used on a small fraction of any screen — its rarity
  is the point.
- **Coral Signal (light-mode text)** (`#C4453B`): contrast-safe darkening of
  the accent for small text (captions/footnotes) on light backgrounds, where
  raw `#F26666` falls below WCAG AA (~3.2:1). Filled coral buttons (white
  text on coral) are unaffected.

### Neutral
- **Void** (`#0E0E0E`, `bgPrimary`): the base canvas in dark mode (Pure Black
  variant). Adapts to `systemBackground` in light mode.
- **Card Surface** (`#1A1A1A`, `bgCard`): the resting surface for cards,
  rows, and grouped content — one step up from Void.
- **Secondary Surface** (`#222222`, `bgSecondary`): toolbar buttons, chips,
  and secondary controls — one step up from Card Surface.
- **Label / Text** (`UIColor.label` family — `textPrimary`,
  `textSecondary`, `textMuted`): adaptive system text colors. Never
  hardcoded gray; always one of these three roles.

### Semantic
- **Income Green** (`#34C759`): income amounts and positive deltas only.
  Never decorative.

### Named Rules
**The One Coral Rule.** Coral (`#F26666`) is the single accent color in the
system. If a screen has more than one coral element competing for attention,
demote one to neutral.

**The Tonal Step Rule.** Depth between sibling surfaces is one tonal step
(Void → Card → Secondary), never a jump of two steps or an arbitrary gray.

## 3. Typography

**Display/Body Font:** SF Pro (system), Dynamic-Type-scaled via
`UIFontMetrics` against the nearest semantic text style (`relativeTo:`).

**Character:** One typeface family, weight and size carry all the
differentiation — confident, quiet, no display/body pairing drama. Numbers
(amounts) get the heaviest weights in the system; everything else stays
regular/medium/semibold.

### Hierarchy
- **Display** (`.black`, 52px / `dsHeroAmount`, `relativeTo: .largeTitle`):
  Today's hero balance amount — the single largest element in the app.
- **Title** (`.bold`, 34px / `dsTitle`, and 26px `.bold` / `dsTitle2Bold`):
  section headers (e.g. "Daily Highlights") and big card numbers.
- **Headline** (`.semibold`, 20px / `dsHeadline`, 17px / `dsSubhead`):
  primary row/section headings.
- **Body** (`.regular`/`.medium`, 16px / `dsBody`, `dsBodyMedium`): default
  reading text, descriptions, list rows.
- **Label** (13px / `dsCaption`, `dsFootnote`; 11px / `dsCaption2`,
  `dsBadge`): captions, axis labels, badges, "/day" suffixes. Never
  uppercase-tracked as a section eyebrow.

### Named Rules
**The Scaled-Token Rule.** Every text element uses a `DSFont` token
(UIFontMetrics-scaled). `Font.system(size:)` with no `relativeTo:` is
forbidden — it breaks Dynamic Type.

## 4. Elevation

Anka conveys depth through **Liquid Glass materials and tonal surface
steps**, never drawn box-shadows. Two depth systems work together:

- **Glass layering**: toolbar buttons, the bottom-bar composer, and sheet
  chrome use `.glassEffect(.regular, in: .capsule/.circle)` — translucent,
  blurred materials that float over content. Interactive glass
  (`.interactive()`) responds to press with a tint shift, not a shadow.
- **Tonal layering**: static content surfaces (cards, rows, grouped lists)
  step from Void (`#0E0E0E`) → Card Surface (`#1A1A1A`) → Secondary Surface
  (`#222222`), each one step lighter than its parent.

### Named Rules
**The No-Shadow Rule.** `box-shadow`/`.shadow()` is forbidden for conveying
hierarchy. Use a glass material (interactive elements) or the next tonal
step (static content) instead.

**The Glass-for-Controls Rule.** Glass materials are reserved for
*interactive* chrome (toolbar buttons, composer, FAB-like Add button).
Static content cards use tonal surfaces, not glass — glassmorphism-as-decor
on a content card is exactly the look this system rejects.

## 5. Components

Tactile glass: interactive controls (buttons, toolbar items, the composer)
are glass capsules/circles that respond to touch with a tint shift; static
content (cards, rows) is flat tonal surfaces with generous padding — no
nested cards, no borders.

### Buttons
- **Shape:** full capsule (`rounded.full`, 999px) for pills/CTAs; circle for
  icon-only toolbar buttons.
- **Primary:** `.glassEffect(.regular.tint(coral-accent).interactive())`,
  white text/icon (`textOnAccent`). Used for Save/Send and the detached Add
  button.
- **Secondary / Toolbar:** `.glassEffect(.regular)`, `tint(.primary)`,
  44×44pt circular tap target (Settings gear, Stats, Filter icons).
- **Hover / Focus:** N/A (touch) — `.interactive()` glass gives a press-time
  tint/scale response; no custom hover states.

### Chips
- **Style:** capsule, `bgSecondary` background when idle; `accentSoft`
  (coral at low opacity) or coral fill when selected/active (e.g. "Filtered
  by …" pill, category bubble).
- **State:** idle = plain icon/label on `bgSecondary`; active = coral tint
  or fill, white/coral text.

### Cards / Containers
- **Corner Style:** `rounded.large` (20px) for top-level cards (Highlights
  cards, summary cards); `rounded.small` (8px) for chart bar corners and
  small inline elements.
- **Background:** `bgCard` (`#1A1A1A`), one tonal step above the page
  background (`bgPrimary`).
- **Shadow Strategy:** none — see Elevation. Separation comes from the tonal
  step alone.
- **Border:** none.
- **Internal Padding:** `spacing.md` (12px) for compact cards;
  `spacing.screenEdge` (20px) for page-level horizontal insets.

### Inputs / Fields
- **Style:** glass capsule (`.glassEffect(.regular, in: .capsule)`) on
  `bgPrimary`/transparent backdrop — e.g. the inline composer's text field
  and category bubble.
- **Focus:** field stays glass; the send button transitions from plain
  `.regular` glass + gray arrow to `.regular.tint(coral-accent).interactive()`
  once input is valid.
- **Error / Disabled:** disabled send stays plain gray glass (no red error
  styling pattern yet — errors surface via system `.alert`).

### Navigation
- Liquid Glass tab bar (iOS 26): left pill is **Today** only, right detached
  button is **Add** (`role: .search`). `.tabBarMinimizeBehavior(.onScrollDown)`.
- Top bar: transparent (`.toolbarBackground(.hidden, for: .navigationBar)`),
  Settings gear top-trailing as a glass circle.
- Bottom toolbar: Filter • Search • Add, also glass circles/capsules, hidden
  while the inline composer is active.
- Sheets/pushes use Mail-style zoom transitions
  (`matchedTransitionSource` + `.navigationTransition(.zoom)`) from the
  triggering toolbar icon, not a plain slide.

## 6. Do's and Don'ts

### Do:
- **Do** use exactly one coral accent (`#F26666`) per screen for the single
  most important element — a CTA, an expense amount, or a selected state.
- **Do** step surfaces by one tonal level at a time: Void (`#0E0E0E`) → Card
  (`#1A1A1A`) → Secondary (`#222222`).
- **Do** use `.glassEffect()` for interactive controls (buttons, toolbar
  items, composer) and reserve flat tonal surfaces for static content.
- **Do** use `DSFont` tokens (UIFontMetrics-scaled) for all text — Dynamic
  Type must work everywhere.
- **Do** use Mail-style zoom transitions (`matchedTransitionSource` +
  `.navigationTransition(.zoom)`) when a sheet/page is opened from a toolbar
  icon, matching Apple's own apps.

### Don't:
- **Don't** build "fintech SaaS dashboard" UI: no gradient hero cards, no
  dense data tables, no identical stat-card grids.
- **Don't** use side-stripe borders (`border-left`/`border-right` accents) on
  cards, rows, or callouts.
- **Don't** use gradient text or `background-clip: text` effects.
- **Don't** add tiny uppercase tracked "eyebrow" labels above sections
  (e.g. "ABOUT", "SPENDING") — Anka has no eyebrow convention.
- **Don't** use `.shadow()`/box-shadow for hierarchy — use glass materials
  (interactive) or the next tonal step (static).
- **Don't** apply glassmorphism decoratively to static content cards —
  glass is reserved for interactive chrome.
- **Don't** hardcode hex colors, font sizes, spacing, or corner radii —
  always go through `DSColor` / `DSFont` / `DSSpacing` / `DSRadius`.
