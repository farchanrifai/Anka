import SwiftUI

/// Shared bar rows — same style as MonthlyHighlightCard's comparisonRow.
/// Proportional colored bars, label inside, amount above, 44 pt height.
struct CategoryBarRows: View {
    let categories: [CategorySpendHighlight]

    var body: some View {
        let maxAmount = categories.first?.amount ?? 1
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            ForEach(categories) { cat in
                barRow(cat, maxAmount: maxAmount)
            }
        }
    }

    private func barRow(_ cat: CategorySpendHighlight, maxAmount: Double) -> some View {
        let ratio = maxAmount > 0 ? cat.amount / maxAmount : 0
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyInfo.info(for: AppCurrency.code).symbol)
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textPrimary)
                Text(cat.amount.idrShort)
                    .font(.dsTitle2Bold)
                    .foregroundStyle(DSColor.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSRadius.small)
                        .fill(Color(hex: cat.colorHex))
                        .frame(width: max(geo.size.width * ratio, 60))
                    Text(cat.emoji + " " + cat.name)
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.white)
                        .padding(.leading, DSSpacing.md)
                        .lineLimit(1)
                }
            }
            .frame(height: 44)
        }
    }
}

struct TopCategoryCard: View {
    let data: TopCategoryHighlightData
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("📊 Categories")
                .font(.dsFootnoteSemi)
                .foregroundStyle(DSColor.accent)

            Text("Your biggest spending area is \(data.categories.first?.name ?? "–") this \(data.monthLabel).")
                .font(.dsBody)
                .foregroundStyle(DSColor.textPrimary)

            Divider().background(Color.gray.opacity(0.3))

            CategoryBarRows(categories: data.categories)

            Divider().background(Color.gray.opacity(0.3))

            Button(action: onSeeAll) {
                HStack {
                    Text("View all categories")
                        .font(.dsFootnoteMedium)
                        .foregroundStyle(DSColor.accentText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.dsCaption2)
                        .foregroundStyle(DSColor.accentText)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(DSSpacing.md)
        .background(DSColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }
}
