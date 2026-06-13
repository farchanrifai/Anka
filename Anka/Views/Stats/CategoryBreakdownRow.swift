import SwiftUI

/// A single row in the Stats sheet's "Spending by category" list: emoji, name,
/// a thin proportion bar in the category's color, the amount, and its share of
/// the month total. Stateless — selection styling is driven by the parent so it
/// stays in sync with the donut (`isDimmed` greys out non-selected rows while a
/// slice is selected).
struct CategoryBreakdownRow: View {
    let data: CategorySpendData
    /// Share of the month total, 0...1. Drives the proportion bar width.
    let fraction: Double
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                // Small colored emoji bubble — echoes TransactionRow's 54pt
                // bubble at a denser scale so the breakdown list feels native.
                ZStack {
                    Circle()
                        .fill(data.color.opacity(DSOpacity.subtle))
                        .frame(width: 32, height: 32)
                    Text(data.emoji)
                        .font(.system(size: 15, relativeTo: .subheadline))
                }

                Text(data.name)
                    .font(.dsBodySemi)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.sm)

                Text(data.amount.rupiah)
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(DSColor.textPrimary)
                    .monospacedDigit()

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            // Proportion bar — track + colored fill scaled to `fraction`.
            // Inset to align with the text, past the emoji bubble.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DSColor.bgSecondary)
                    Capsule()
                        .fill(data.color)
                        .frame(width: max(geo.size.width * fraction, 3))
                }
            }
            .frame(height: 5)
            .padding(.leading, 32 + DSSpacing.md)
        }
        .opacity(isDimmed ? DSOpacity.muted : 1)
        .contentShape(Rectangle())
        // Collapse the row's sub-elements into one VoiceOver element that reads
        // "Groceries, Rp 1,840,000, 38 percent" (AUDIT.md AC2).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.name)
        .accessibilityValue("\(data.amount.rupiah), \(Int((fraction * 100).rounded())) percent")
    }
}

#Preview {
    VStack(spacing: DSSpacing.lg) {
        CategoryBreakdownRow(
            data: CategorySpendData(id: "1", name: "Groceries", emoji: "🛒", color: Color(hex: "#F26666"), amount: 1_840_000),
            fraction: 0.38,
            isDimmed: false
        )
        CategoryBreakdownRow(
            data: CategorySpendData(id: "2", name: "Car", emoji: "🚗", color: Color(hex: "#42A5F5"), amount: 1_080_000),
            fraction: 0.22,
            isDimmed: true
        )
    }
    .padding()
    .background(DSColor.bgPrimary)
}
