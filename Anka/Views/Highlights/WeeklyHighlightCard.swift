import Charts
import SwiftUI

/// Apple Health-style weekly card: bar per day + a coral rule line at the average.
struct WeeklyHighlightCard: View {
    let data: WeeklyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("💰 Spending")
                .font(.dsFootnoteSemi)
                .foregroundStyle(DSColor.accent)

            Text(data.descriptiveText)
                .font(.dsBody)
                .foregroundStyle(DSColor.textPrimary)

            Divider().background(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 2) {
                Text("Average Spend")
                    .font(.dsCaption)
                    .foregroundStyle(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(CurrencyInfo.info(for: AppCurrency.code).symbol).font(.dsCaption).foregroundStyle(DSColor.textPrimary)
                    Text(data.dailyAverage.idrShort).font(.dsTitle2Bold).foregroundStyle(DSColor.textPrimary)
                }
            }

            Chart {
                ForEach(data.days, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Spend", day.total)
                    )
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .cornerRadius(DSRadius.small)
                }
                RuleMark(y: .value("Average", data.dailyAverage))
                    .foregroundStyle(DSColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .frame(height: 160)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: data.days.map(\.date)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel(weekdayLetter(date))
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }

    private func weekdayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: date) - 1
        return String(symbols[index].prefix(1))
    }
}
