import SwiftUI
import UIKit
import Charts

// Ported verbatim from Spendy (DonutChartView.swift). Only the coral accent
// constant changed (Color.spendyCoral → DSColor.accent — both are #F26666).
// Animations, gestures, fonts, ratios, haptics, and tap/swipe detection are
// preserved exactly so the visual + interaction feel matches Spendy.

struct CategorySpendData: Identifiable {
    let id: String
    let name: String
    let color: Color
    let amount: Double
}

struct DonutChartView: View {
    let categoryData: [CategorySpendData]
    let totalSpent: Double
    let budget: Double
    let monthName: String
    let onSetBudget: () -> Void
    var onSwipe: ((Int) -> Void)? = nil

    @State private var selectedCategory: CategorySpendData? = nil
    @State private var chartSize: CGSize = .zero
    @State private var dragIsSwipe = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)

    private let innerRatio: CGFloat = 0.78

    private var slices: [CategorySpendData] {
        categoryData.isEmpty
            ? [CategorySpendData(id: "_placeholder", name: "_placeholder", color: Color(.systemGray5), amount: 1)]
            : categoryData
    }

    private var displayAmount: Double {
        selectedCategory?.amount ?? totalSpent
    }

    private var displayLabel: String {
        selectedCategory?.name ?? monthName
    }

    private var dataSignature: String {
        categoryData.map(\.id).joined(separator: "|") + "|\(monthName)"
    }

    var body: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", max(slice.amount, 0.001)),
                    innerRadius: .ratio(innerRatio),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color)
                .cornerRadius(3)
                .opacity(selectedCategory == nil || selectedCategory?.id == slice.id ? 1 : 0.35)
            }
            .id(dataSignature)
            .transition(.opacity)

            // Transparent gesture layer above the chart, below the center label.
            // Putting the gesture on its own view (not on Chart) avoids fighting
            // Swift Charts' internal touch handling — that was the freeze/crash source.
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onAppear { chartSize = geo.size }
                    .onChange(of: geo.size) { _, s in chartSize = s }
                    // Simultaneous (not exclusive) so a vertical drag that
                    // starts on the donut can still be claimed by the
                    // enclosing sheet's swipe-to-dismiss — donutGesture's
                    // own onEnded already no-ops for non-horizontal drags.
                    .simultaneousGesture(donutGesture)
            }

            VStack(spacing: 4) {
                Text(displayLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .animation(.easeInOut(duration: 0.2), value: displayLabel)

                Text(displayAmount.idrShort)
                    .font(.system(size: 23, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: displayAmount)

                if let selected = selectedCategory {
                    let pct = totalSpent > 0 ? selected.amount / totalSpent * 100 : 0
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: pct)
                } else {
                    Button(action: onSetBudget) {
                        Text(budget > 0 ? "Budget: \(budget.idrFormatted)" : "Set Budget >")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(budget > 0 ? Color.secondary : DSColor.accent)
                    }
                }
            }
            .padding(.horizontal, 60)
        }
        .animation(.easeInOut(duration: 0.25), value: dataSignature)
        .onChange(of: totalSpent) { _, _ in
            selectedCategory = nil
        }
    }

    private var donutGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                if !dragIsSwipe && dx + dy > 12 && dx > dy * 1.8 {
                    dragIsSwipe = true
                }
            }
            .onEnded { value in
                let wasSwipe = dragIsSwipe
                dragIsSwipe = false
                if wasSwipe, abs(value.predictedEndTranslation.width) > 60 {
                    onSwipe?(value.translation.width < 0 ? 1 : -1)
                    return
                }
                let movedFar = abs(value.translation.width) > 10 || abs(value.translation.height) > 10
                guard !movedFar else { return }
                guard let hit = sector(at: value.startLocation) else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedCategory = (selectedCategory?.id == hit.id) ? nil : hit
                }
                haptic.impactOccurred()
            }
    }

    // Returns the category whose sector contains the tap location.
    private func sector(at location: CGPoint) -> CategorySpendData? {
        guard !categoryData.isEmpty, chartSize.width > 0, chartSize.height > 0 else { return nil }

        let center = CGPoint(x: chartSize.width / 2, y: chartSize.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        let outerRadius = min(chartSize.width, chartSize.height) / 2
        let inner = outerRadius * innerRatio
        guard distance >= inner && distance <= outerRadius else { return nil }

        // Angle from top (12 o'clock), clockwise, normalised to [0, 2π)
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let total = categoryData.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        var cumulative = 0.0
        for cat in categoryData {
            cumulative += cat.amount / total * 2 * .pi
            if angle <= cumulative { return cat }
        }
        return categoryData.last
    }
}

#Preview {
    DonutChartView(
        categoryData: [
            CategorySpendData(id: "1", name: "Groceries", color: Color(hex: "#FF6B6B"), amount: 400000),
            CategorySpendData(id: "2", name: "Car",       color: Color(hex: "#42A5F5"), amount: 200000),
            CategorySpendData(id: "3", name: "Coffee",    color: Color(hex: "#FF8A65"), amount:  44271),
        ],
        totalSpent: 644271,
        budget: 5_000_000,
        monthName: "May",
        onSetBudget: {}
    )
    .frame(height: 280)
    .padding()
}
