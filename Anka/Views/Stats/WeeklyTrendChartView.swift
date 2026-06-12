import SwiftUI
import Charts

/// Horizontal bar chart of weekly expense totals for the Stats sheet.
/// Scrolls horizontally when there are more weeks than fit on screen. A dashed
/// reference line marks the weekly average; tapping a bar reveals that week's
/// total + date range in the section header.
struct WeeklyTrendChartView: View {
    let weeklyData: [WeeklySpendData]
    /// Mean spend across weeks that had any spend — drives the reference line.
    let average: Double

    @State private var selectedLabel: String?

    /// The week the user is scrubbing, resolved from the selected x-axis label.
    private var selectedWeek: WeeklySpendData? {
        guard let selectedLabel else { return nil }
        return weeklyData.first { $0.label == selectedLabel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            header

            if weeklyData.isEmpty || weeklyData.allSatisfy({ $0.total == 0 }) {
                emptyState
            } else {
                chart
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Weekly trend")
                .font(.dsSubheadSemi)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
            if let week = selectedWeek {
                Text("\(week.dateRangeLabel) · Rp \(week.total.idrShort)")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
            } else if average > 0 {
                Text("avg Rp \(average.idrShort)")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .animation(.dsEase, value: selectedLabel)
    }

    private var emptyState: some View {
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
    }

    private var chart: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Chart(weeklyData) { week in
                BarMark(
                    x: .value("Week", week.label),
                    y: .value("Total", week.total)
                )
                .foregroundStyle(DSColor.accent)
                .opacity(selectedLabel == nil || selectedLabel == week.label ? 1 : DSOpacity.muted)
                .cornerRadius(4)

                if average > 0 {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(DSColor.textMuted)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisValueLabel()
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                }
            }
            .chartXSelection(value: $selectedLabel)
            .frame(minWidth: weeklyData.count > 4 ? CGFloat(weeklyData.count * 60 + 40) : nil)
            .frame(height: 180)
            .padding(.horizontal, DSSpacing.screenEdge)
        }
    }
}

#Preview {
    WeeklyTrendChartView(
        weeklyData: [
            WeeklySpendData(weekStart: Calendar.current.date(byAdding: .day, value: -14, to: .now.startOfWeek)!, weekEnd: Calendar.current.date(byAdding: .day, value: -7, to: .now.startOfWeek)!, total: 410_000, weekNumber: 1),
            WeeklySpendData(weekStart: Calendar.current.date(byAdding: .day, value: -7, to: .now.startOfWeek)!, weekEnd: .now.startOfWeek, total: 250_000, weekNumber: 2),
            WeeklySpendData(weekStart: .now.startOfWeek, weekEnd: Calendar.current.date(byAdding: .day, value: 7, to: .now.startOfWeek)!, total: 690_000, weekNumber: 3),
        ],
        average: 450_000
    )
    .padding(.vertical)
    .background(DSColor.bgPrimary)
}
