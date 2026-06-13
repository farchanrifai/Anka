import SwiftUI

/// The dashboard's period selector. Tapping it opens a menu that lets the user
/// jump straight to any recent month (the discoverable, VoiceOver-reachable
/// alternative to the swipe-only navigation the audit flagged in U2) or open
/// the full period/category filter sheet. Shared by both Today view variants.
struct PeriodMenuPill: View {
    @Bindable var vm: TodayViewModel

    var body: some View {
        Menu {
            Section("Jump to Month") {
                ForEach(vm.recentMonths(), id: \.self) { month in
                    Button {
                        withAnimation(.dsSnappy) { vm.jumpToMonth(month) }
                    } label: {
                        if isSelected(month) {
                            Label(monthTitle(month), systemImage: "checkmark")
                        } else {
                            Text(monthTitle(month))
                        }
                    }
                }
            }

            Divider()

            Button {
                vm.showCategoryFilter = true
            } label: {
                Label("More Filters…", systemImage: "line.3.horizontal.decrease.circle")
            }
        } label: {
            Text(vm.periodPillLabel)
                .font(.dsFootnoteMedium)
                .lineLimit(1)
                .contentTransition(.numericText())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(DSColor.textOnAccent)
                .background(DSColor.accent, in: Capsule())
                .animation(.dsSnappy, value: vm.periodPillLabel)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Period: \(vm.periodPillLabel). Opens month picker.")
    }

    /// "This Month" for the live month, otherwise "May 2026".
    private func monthTitle(_ month: Date) -> String {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
            ? "This Month"
            : month.monthYearLabel
    }

    private func isSelected(_ month: Date) -> Bool {
        vm.selectedPeriod == .month &&
            Calendar.current.isDate(vm.selectedMonth, equalTo: month, toGranularity: .month)
    }
}

/// Small coral chip shown next to the period pill while the dashboard is
/// browsing a past month or a preset period — one tap returns to the live
/// current month (U2's "Back to <current month>" affordance).
struct BackToCurrentMonthChip: View {
    @Bindable var vm: TodayViewModel

    var body: some View {
        Button {
            withAnimation(.dsSnappy) { vm.resetToCurrentMonth() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.dsCaption2Bold)
                Text(Date().monthName)
                    .font(.dsFootnoteMedium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(DSColor.accent)
            .background(DSColor.accent.opacity(DSOpacity.subtle), in: Capsule())
        }
        .buttonStyle(.pressable)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Back to \(Date().monthName)")
    }
}
