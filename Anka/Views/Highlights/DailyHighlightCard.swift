import Charts
import SwiftUI

/// Apple Health-style daily card: Today vs Average dual stat, plus a
/// cumulative stair-step chart (today vs typical) with a "now" marker.
/// Falls back to the dual stat alone when there isn't enough data to chart.
struct DailyHighlightCard: View {
    let data: DailyHighlightData

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("💰 Spending")
                .font(.dsCaption)
                .foregroundStyle(DSColor.accent)

            Text(data.descriptiveText)
                .font(.dsBody)
                .foregroundStyle(DSColor.textPrimary)

            Divider().background(Color.gray.opacity(0.3))

            HStack(spacing: DSSpacing.lg) {
                statColumn(dot: DSColor.accent, label: "Today", amount: data.todayTotal, color: DSColor.accent)
                statColumn(dot: .gray, label: "Average", amount: data.averageTotal, color: .gray)
            }

            if data.hasEnoughDataForChart {
                Chart {
                    ForEach(data.cumulativeAverage, id: \.time) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Cumulative", point.amount),
                            series: .value("Series", "Average")
                        )
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(data.cumulativeToday, id: \.time) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Cumulative", point.amount),
                            series: .value("Series", "Today")
                        )
                        .foregroundStyle(DSColor.accent)
                        .interpolationMethod(.stepEnd)
                    }
                    RuleMark(x: .value("Now", data.currentTimeMarker))
                        .foregroundStyle(Color.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .frame(height: 180)
                .chartYAxis(.hidden)
            }
        }
        .padding(DSSpacing.md)
        .background(DSColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }

    private func statColumn(dot: Color, label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(label).font(.dsCaption).foregroundStyle(color)
            }
            Text(amount.rupiah)
                .font(.dsTitle2Bold)
                .foregroundStyle(color)
        }
    }
}
