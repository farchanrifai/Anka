import SwiftUI

/// Empty state for the Today list. Renders two variants:
///   • `isUnfiltered` (no transactions exist at all) → "Add Transaction" CTA
///   • otherwise (filters/period yield nothing) → optional "Clear Filters"
/// Shared by the Today view variants.
struct TransactionEmptyStateView: View {
    /// True when the user has no transactions at all (vs. an active filter
    /// that simply matched nothing).
    let isUnfiltered: Bool
    /// True when a category filter is active (drives the "Clear Filters" CTA).
    let hasActiveFilter: Bool
    let onAdd: () -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: isUnfiltered ? "tray" : "magnifyingglass")
                .font(.system(size: 48, relativeTo: .largeTitle))
                .foregroundStyle(.tertiary)
                // Subtle one-shot bounce when the empty state (re)appears.
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.bottom, DSSpacing.xs)

            VStack(spacing: DSSpacing.xs) {
                Text(isUnfiltered ? "No Transactions Yet" : "No Matches Found")
                    .font(.dsHeadlineSemi)
                    .foregroundStyle(.primary)

                Text(isUnfiltered
                     ? "Tap the button below to add your first expense or income."
                     : "No transactions match the selected period or filters.")
                    .font(.dsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isUnfiltered {
                Button(action: onAdd) {
                    Text("Add Transaction")
                        .font(.dsSubheadSemi)
                        .foregroundStyle(DSColor.bgPrimary)
                        .padding(.horizontal, DSSpacing.screenEdge)
                        .padding(.vertical, 10)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, DSSpacing.sm)
            } else if hasActiveFilter {
                Button(action: onClearFilter) {
                    Text("Clear Filters")
                        .font(.dsBodyMedium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColor.bgSecondary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, DSSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, DSSpacing.xxl)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
