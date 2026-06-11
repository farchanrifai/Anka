import SwiftUI
import Charts

/// Horizontal bar chart of weekly expense totals for the Stats sheet.
/// Scrolls horizontally when there are more weeks than fit on screen.
struct WeeklyTrendChartView: View {
    let weeklyData: [WeeklySpendData]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Weekly trend")
                .font(.dsHeadline)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.screenEdge)

            if weeklyData.isEmpty || weeklyData.allSatisfy({ $0.total == 0 }) {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "calendar")
                        .font(.system(size: 32, relativeTo: .title))
                        .foregroundStyle(DSColor.textMuted)
                    Text("No expenses this period")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(DSColor.bgSecondary, in: RoundedRectangle(cornerRadius: DSRadius.medium))
                .padding(.horizontal, DSSpacing.screenEdge)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Chart(weeklyData) { week in
                        BarMark(
                            x: .value("Week", week.label),
                            y: .value("Total", week.total)
                        )
                        .foregroundStyle(DSColor.accent)
                        .cornerRadius(4)
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(position: .bottom) { _ in
                            AxisValueLabel()
                                .font(.dsCaption)
                                .foregroundStyle(DSColor.textMuted)
                        }
                    }
                    .frame(minWidth: weeklyData.count > 4 ? CGFloat(weeklyData.count * 60 + 40) : nil)
                    .frame(height: 180)
                    .padding(.horizontal, DSSpacing.screenEdge)
                }
            }
        }
    }
}

#Preview {
    WeeklyTrendChartView(weeklyData: [
        WeeklySpendData(weekStart: Calendar.current.date(byAdding: .day, value: -7, to: .now.startOfWeek)!, weekEnd: .now.startOfWeek, total: 410_000, weekNumber: 1),
        WeeklySpendData(weekStart: .now.startOfWeek, weekEnd: Calendar.current.date(byAdding: .day, value: 7, to: .now.startOfWeek)!, total: 250_000, weekNumber: 2),
    ])
    .padding(.vertical)
    .background(DSColor.bgPrimary)
}
