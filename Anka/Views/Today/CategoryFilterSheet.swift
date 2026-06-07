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

    private var expense: [Category] { allCategories.filter { $0.type == .expense } }
    private var income:  [Category] { allCategories.filter { $0.type == .income  } }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Filter by Category")
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
                Text(cat.emoji).font(.system(size: 22))
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
}

#Preview {
    @Previewable @State var selection: [Category] = []
    return CategoryFilterSheet(selection: $selection)
        .modelContainer(SampleData.container())
}
