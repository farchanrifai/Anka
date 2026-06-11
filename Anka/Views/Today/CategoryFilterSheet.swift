import SwiftUI
import SwiftData

/// Multi-select category filter, presented from the Today bottom toolbar's
/// Filter button. Mirrors the iOS Mail filter-sheet pattern: native List with
/// section headers, checkmarks for selected rows, and a "Clear All" action.
struct CategoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    /// Two-way binding with TodayViewModel.selectedCategories.
    @Binding var selection: [Category]
    @Binding var selectedPeriod: PeriodFilter
    @Binding var customStartDate: Date?
    @Binding var customEndDate: Date?

    private var expense: [Category] { allCategories.filter { $0.type == .expense } }
    private var income:  [Category] { allCategories.filter { $0.type == .income  } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPills
                
                Divider()
                
                List {
                    if !expense.isEmpty {
                        Section("Expense") {
                            ForEach(expense, id: \.id) { row($0) }
                        }
                    }
                    if !income.isEmpty {
                        Section("Income") {
                            ForEach(income, id: \.id) { row($0) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(.clear)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                    .tint(DSColor.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(DSColor.accent)
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }

    @ViewBuilder
    private func row(_ cat: Category) -> some View {
        let isSelected = selection.contains { $0.id == cat.id }
        Button {
            if isSelected {
                selection.removeAll { $0.id == cat.id }
            } else {
                selection.append(cat)
            }
        } label: {
            HStack(spacing: 12) {
                Text(cat.emoji).font(.system(size: 22, relativeTo: .title2))
                Text(cat.name)
                    .font(.dsBody)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.dsFootnoteSemi)
                        .foregroundStyle(DSColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Period Pills

    private var periodPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PeriodFilter.filterOptions, id: \.self) { period in
                    if period == .custom {
                        NavigationLink {
                            DateRangePicker(startDate: $customStartDate, endDate: $customEndDate)
                                .navigationTitle("Select Dates")
                                .navigationBarTitleDisplayMode(.inline)
                                .onAppear {
                                    selectedPeriod = .custom
                                }
                        } label: {
                            pillLabel(for: period)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            withAnimation(.dsSpring) {
                                selectedPeriod = period
                                customStartDate = nil
                                customEndDate = nil
                            }
                        } label: {
                            pillLabel(for: period)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.screenEdge)
            .padding(.vertical, 12)
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private func pillLabel(for period: PeriodFilter) -> some View {
        let isSelected = selectedPeriod == period

        HStack(spacing: 6) {
            if period == .custom {
                Image(systemName: "calendar")
            }
            Text(period.displayString)
        }
        .font(.dsFootnoteSemi)
        .foregroundStyle(isSelected ? DSColor.textOnAccent : DSColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? DSColor.accent : DSColor.bgSecondary, in: Capsule())
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}

#Preview {
    @Previewable @State var selection: [Category] = []
    @Previewable @State var selectedPeriod: PeriodFilter = .month
    @Previewable @State var customStartDate: Date? = nil
    @Previewable @State var customEndDate: Date? = nil
    return CategoryFilterSheet(
        selection: $selection,
        selectedPeriod: $selectedPeriod,
        customStartDate: $customStartDate,
        customEndDate: $customEndDate
    )
    .modelContainer(SampleData.container())
}
