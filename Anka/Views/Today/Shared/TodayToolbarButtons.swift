import SwiftUI

// Shared toolbar buttons for the Today view variants. Each reads/writes the
// shared `TodayViewModel`, so the two views present identical bar items.

/// Bottom-bar Filter control. Idle → plain icon (system renders a circle);
/// active → "Filtered by <label> ⌄". Sources the filter sheet's zoom transition.
struct FilterToolbarButton: View {
    let vm: TodayViewModel
    let namespace: Namespace.ID

    var body: some View {
        Button {
            vm.showCategoryFilter = true
        } label: {
            if let label = vm.filterLabel {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "line.3.horizontal.decrease")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Filtered by")
                            .font(.dsCaption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Text(label)
                                .font(.dsFootnoteSemi)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.dsCaption2Semi)
                        }
                    }
                }
            } else {
                Image(systemName: "line.3.horizontal.decrease")
            }
        }
        .tint(vm.filterLabel == nil ? .primary : DSColor.accent)
        .accessibilityLabel(accessibilityLabel)
        // Mail-style zoom: sheet expands out of the filter button.
        .matchedTransitionSource(id: "filter", in: namespace)
    }

    private var accessibilityLabel: String {
        if let label = vm.filterLabel { return "Filtered by \(label). Tap to edit." }
        return "Filter"
    }
}

/// Bottom-bar Add control. Sources the Add sheet's zoom transition.
struct AddToolbarButton: View {
    let vm: TodayViewModel
    let namespace: Namespace.ID

    var body: some View {
        Button {
            vm.showAddTransaction = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(DSColor.textOnAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(DSColor.accent)
        .accessibilityLabel("Add transaction")
        .matchedTransitionSource(id: "addTransaction", in: namespace)
    }
}

/// Top-bar Stats control. Sources the Stats sheet's zoom transition.
struct StatsToolbarButton: View {
    let vm: TodayViewModel
    let namespace: Namespace.ID

    var body: some View {
        Button { vm.showStats = true } label: {
            Image(systemName: "chart.pie")
        }
        .tint(.primary)
        .accessibilityLabel("Stats")
        .matchedTransitionSource(id: "stats", in: namespace)
    }
}

/// Top-bar Settings control.
struct SettingsToolbarButton: View {
    let vm: TodayViewModel

    var body: some View {
        Button { vm.showSettings = true } label: {
            Image(systemName: "gearshape")
        }
        .tint(.primary)
        .accessibilityLabel("Settings")
    }
}
