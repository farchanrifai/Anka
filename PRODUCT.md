# Product

## Register

product

## Users

A single global user managing their own personal finances on iOS — no
collaboration, no accounts to manage for others. They want to log an expense
in seconds, glance at where their money went, and trust the app to be quiet
and accurate. Primary jobs: fast manual entry (numpad/NL parsing), quick
"how am I doing" checks (Today hero, Stats, Highlights), and occasional
housekeeping (categories, backup/export, appearance, app lock).

## Product Purpose

Anka is a personal expense tracker: manual-entry first, fast logging,
beautiful opinionated design. "It just works." Success looks like a user who
opens the app, logs a transaction in a few taps, and closes it again —
the design should never be the thing they notice.

## Brand Personality

Sleek & premium, calm, native. Anka should feel like it ships with iOS, not
bolted onto it — confident, understated, Apple-native polish (Liquid Glass,
SF fonts, system motion curves). Coral accent (#F26666) is the one splash of
personality against a dark, neutral base.

## Anti-references

Apple Health / Wallet / Reminders are the north star — spare layouts, generous
whitespace, restrained color, native components over custom chrome.

Explicitly avoid the "fintech SaaS dashboard" look: gradient hero cards,
dense data tables, side-stripe accent borders, identical stat-card grids,
tiny uppercase eyebrow labels, or anything that reads as a web dashboard
ported to iOS.

## Design Principles

- Native-first: reach for system components, SF fonts, and platform motion
  before building custom chrome.
- One accent, used deliberately: coral (#F26666) marks the primary action or
  highlight, not decoration.
- Quiet by default: dark, neutral surfaces; let data and the accent carry
  emphasis.
- Tokens only: all views use DSColor/DSFont/DSRadius/DSSpacing — no hardcoded
  hex, sizes, or radii.
- Low friction over feature density: every screen should serve "log it fast"
  or "see it clearly" — no feature creep.

## Accessibility & Inclusion

Standard iOS accessibility: Dynamic Type via UIFontMetrics-scaled DSFont
tokens, VoiceOver labels on toolbar/interactive elements, adaptive light/dark
appearance with a dark-variant option (Pure Black / Soft Dark).
