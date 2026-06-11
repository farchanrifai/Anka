import SwiftUI

/// Pure display label for a transaction amount, rendered as a rounded capsule
/// (e.g. `Rp 12,345` for an expense, `+ Rp 12,345` for income). The leading
/// sign is derived from the transaction `type`. No business logic — display only.
///
/// Visual style is lifted verbatim from the original inline amount capsule in
/// `TransactionRow`: `dsFootnoteMedium`, primary foreground, on a
/// `DSColor.bgSecondary` capsule.
struct AmountLabel: View {
    let amount: Double
    let type: TransactionType

    var body: some View {
        let isIncome = type == .income
        Text("\(isIncome ? "+ " : "")Rp \(amount.idrShort)")
            .font(.dsFootnoteMedium)
            // Income reads green so the list scans at a glance; expenses stay
            // neutral (they're the common case — coloring them would be noise).
            .foregroundStyle(isIncome ? DSColor.positive : Color.primary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 6)
            .background(
                isIncome ? DSColor.positive.opacity(0.12) : DSColor.bgSecondary,
                in: Capsule()
            )
    }
}

#Preview {
    HStack(spacing: DSSpacing.md) {
        AmountLabel(amount: 12_345, type: .expense)
        AmountLabel(amount: 250_000, type: .income)
    }
    .padding()
}
