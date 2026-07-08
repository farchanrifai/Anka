import SwiftUI
import Charts

/// Fixed-width line + area chart for Main Page V2.
/// `.chartXSelection` gives an interpolated Date; snap to the nearest data
/// point by time distance to avoid the "jumping dot" glitch from boundary
/// mismatches.
struct MainPageV2LineChart: View {
    let series: [DailySpendPoint]

    @State private var selectedDate: Date?

    private var selectedPoint: DailySpendPoint? {
        guard let sel = selectedDate, !series.isEmpty else { return nil }
        return series.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Tooltip line — fixed height so chart doesn't shift on
            // appear/disappear.
            Group {
                if let point = selectedPoint {
                    Text("\(Self.dayFormatter.string(from: point.date))  \(point.total.rupiah)")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    Text(" ").font(.dsCaption)
                }
            }
            .animation(.dsEase, value: selectedPoint?.date)

            if series.isEmpty || series.allSatisfy({ $0.total == 0 }) {
                Rectangle()
                    .fill(DSColor.bgSecondary)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        Chart(series) { point in
            AreaMark(
                x: .value("Day", point.date),
                y: .value("Total", point.total)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [DSColor.accent.opacity(DSOpacity.subtle), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Day", point.date),
                y: .value("Total", point.total)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(DSColor.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))

            // Selection indicator: stable vertical rule at the snapped point.
            if let sp = selectedPoint, sp.id == point.id {
                RuleMark(x: .value("Day", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(DSColor.textMuted)

                PointMark(
                    x: .value("Day", point.date),
                    y: .value("Total", point.total)
                )
                .foregroundStyle(DSColor.accent)
                .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedDate)
        .animation(.dsEaseSlow, value: series)
        .frame(height: 160)
    }
}

#Preview {
    let cal = Calendar.current
    let sorted = (0..<30).reversed().map { i in
        DailySpendPoint(
            date: cal.startOfDay(for: cal.date(byAdding: .day, value: -i, to: .now)!),
            total: Double.random(in: 0...300_000)
        )
    }
    return MainPageV2LineChart(series: sorted)
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.vertical)
        .background(DSColor.bgPrimary)
}
