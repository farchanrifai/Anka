import SwiftData
import SwiftUI

/// Apple Health-inspired Highlights page: Daily, Weekly, and Monthly spending
/// cards, computed on-device by `HighlightInsightEngine`. Complements (does
/// not replace) the Stats sheet — always relative to "today", independent of
/// the dashboard's selected period.
struct HighlightsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var daily: DailyHighlightData?
    @State private var weekly: WeeklyHighlightData?
    @State private var monthly: MonthlyHighlightData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if let daily, let weekly, let monthly {
                    section("Daily Highlights") { DailyHighlightCard(data: daily) }
                    section("Weekly Highlights") { WeeklyHighlightCard(data: weekly) }
                    section("Monthly Highlights") { MonthlyHighlightCard(data: monthly) }
                } else {
                    emptyState
                }
            }
            .padding(DSSpacing.screenEdge)
        }
        .background(DSColor.bgPrimary)
        .navigationTitle("Highlights")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard daily == nil else { return }
            let engine = HighlightInsightEngine(modelContext: modelContext)
            daily = engine.dailyHighlight()
            weekly = engine.weeklyHighlight()
            monthly = engine.monthlyHighlight()
        }
    }

    private func section(_ title: String, @ViewBuilder card: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title)
                .font(.dsTitle2Bold)
                .foregroundStyle(DSColor.textPrimary)
            card()
        }
    }

    private var emptyState: some View {
        Text("Not enough data yet — add a few transactions to see your highlights.")
            .font(.dsBody)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.xxl)
    }
}
