import SwiftUI

/// Empty state for the Today list. Renders three variants:
///   • `isUnfiltered` (no transactions exist at all) → "Add Transaction" CTA
///   • `isSearchActive` (search query matched nothing) → "Clear Search" CTA
///   • otherwise (category/period filter yields nothing) → optional "Clear Filters"
/// Shared by the Today view variants.
struct TransactionEmptyStateView: View {
    /// True when the user has no transactions at all (vs. an active filter
    /// that simply matched nothing).
    let isUnfiltered: Bool
    /// True when a category filter is active (drives the "Clear Filters" CTA).
    let hasActiveFilter: Bool
    /// True when a non-empty search query is the reason nothing shows — gets its
    /// own message + "Clear Search" action (AUDIT.md U6).
    var isSearchActive: Bool = false
    let onAdd: () -> Void
    let onClearFilter: () -> Void
    var onClearSearch: () -> Void = {}

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: isUnfiltered ? "tray" : "magnifyingglass")
                .font(.system(size: 48, relativeTo: .largeTitle))
                .foregroundStyle(.tertiary)
                // Subtle one-shot bounce when the empty state (re)appears.
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.bottom, DSSpacing.xs)

            VStack(spacing: DSSpacing.xs) {
                Text(titleText)
                    .font(.dsHeadlineSemi)
                    .foregroundStyle(.primary)

                Text(messageText)
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
            } else if isSearchActive {
                pillButton(title: "Clear Search", action: onClearSearch)
            } else if hasActiveFilter {
                pillButton(title: "Clear Filters", action: onClearFilter)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, DSSpacing.xxl)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var titleText: String {
        if isUnfiltered { return "No Transactions Yet" }
        if isSearchActive { return "No Results" }
        return "No Matches Found"
    }

    private var messageText: String {
        if isUnfiltered { return "Tap the button below to add your first expense or income." }
        if isSearchActive { return "No transactions match your search." }
        return "No transactions match the selected period or filters."
    }

    private func pillButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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
