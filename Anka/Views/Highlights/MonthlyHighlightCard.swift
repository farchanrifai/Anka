import SwiftUI

/// Apple Health-style monthly card: two proportional comparison bars,
/// this month (coral) vs last month (gray), both as a daily average.
struct MonthlyHighlightCard: View {
    let data: MonthlyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("💰 Spending")
                .font(.dsFootnoteSemi)
                .foregroundStyle(DSColor.accent)

            Text(data.descriptiveText)
                .font(.dsBody)
                .foregroundStyle(DSColor.textPrimary)

            Divider().background(Color.gray.opacity(0.3))

            let maxAmount = max(data.thisMonthAvgPerDay, data.lastMonthAvgPerDay)

            comparisonRow(amount: data.thisMonthAvgPerDay, label: data.thisMonthLabel,
                          color: DSColor.accent, maxAmount: maxAmount)
            comparisonRow(amount: data.lastMonthAvgPerDay, label: data.lastMonthLabel,
                          color: Color.gray.opacity(0.4), maxAmount: maxAmount)
        }
        .padding(DSSpacing.md)
        .background(DSColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }

    private func comparisonRow(amount: Double, label: String, color: Color, maxAmount: Double) -> some View {
        let ratio = maxAmount > 0 ? amount / maxAmount : 0
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyInfo.info(for: AppCurrency.code).symbol).font(.dsCaption).foregroundStyle(DSColor.textPrimary)
                Text(amount.idrShort).font(.dsTitle2Bold).foregroundStyle(DSColor.textPrimary)
                Text("/day")
                    .font(.dsCaption)
                    .foregroundStyle(.gray)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSRadius.small)
                        .fill(color)
                        .frame(width: max(geo.size.width * ratio, 60))
                    Text(label)
                        .font(.dsCaptionMedium)
                        .foregroundStyle(color == DSColor.accent ? .white : DSColor.textPrimary)
                        .padding(.leading, DSSpacing.md)
                }
            }
            .frame(height: 44)
        }
    }
}
