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
        let sign = type == .expense ? "" : "+ "
        Text("\(sign)Rp \(amount.idrShort)")
            .font(.dsFootnoteMedium)
            .foregroundStyle(.primary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 6)
            .background(DSColor.bgSecondary, in: Capsule())
    }
}

#Preview {
    HStack(spacing: DSSpacing.md) {
        AmountLabel(amount: 12_345, type: .expense)
        AmountLabel(amount: 250_000, type: .income)
    }
    .padding()
}
