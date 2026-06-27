import SwiftData
import SwiftUI

/// Apple Health-inspired Highlights page: Daily, Weekly, and Monthly spending
/// cards, computed on-device by `HighlightInsightEngine`. Complements (does
/// not replace) the Stats sheet — always relative to "today", independent of
/// the dashboard's selected period.
struct HighlightsView: View {
    let namespace: Namespace.ID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var topCategories: TopCategoryHighlightData?
    @State private var daily: DailyHighlightData?
    @State private var weekly: WeeklyHighlightData?
    @State private var monthly: MonthlyHighlightData?
    @State private var showCategoryDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if let daily, let weekly, let monthly {
                    if let topCategories {
                        section("Category Breakdown") {
                            TopCategoryCard(data: topCategories) { showCategoryDetail = true }
                        }
                    }
                    section("Daily Highlights") { DailyHighlightCard(data: daily) }
                    section("Weekly Highlights") { WeeklyHighlightCard(data: weekly) }
                    section("Monthly Highlights") { MonthlyHighlightCard(data: monthly) }
                } else {
                    emptyState
                }
            }
            .padding(DSSpacing.screenEdge)
        }
        .background(DSColor.bgGrouped)
        .navigationTitle("Highlights")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .tint(.primary)
                .accessibilityLabel("Close")
            }
        }
        .navigationTransition(.zoom(sourceID: "highlights", in: namespace))
        .sheet(isPresented: $showCategoryDetail) {
            NavigationStack { CategoryBreakdownDetailView() }
        }
        .onAppear {
            guard daily == nil else { return }
            let engine = HighlightInsightEngine(modelContext: modelContext)
            topCategories = engine.topCategoryHighlight()
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
