import SwiftUI
import SwiftData

/// Compact V3-styled edit sheet — Liquid Glass field row + date chip + note
/// field + delete/save, matching the inline composer's visual vocabulary.
/// Used only for `TransactionEntryLayout.v3`; V1 keeps the full-form
/// `AddTransactionView` edit sheet (with tags). No tag editing here — existing
/// tags are preserved via `AddTransactionViewModel.loadExisting`/`save`.
struct EditTransactionSheet: View {
    let transaction: Transaction

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var vm: AddTransactionViewModel
    @State private var showDeleteAlert = false
    @State private var saveErrorMessage: String?
    @FocusState private var amountFocused: Bool
    @Namespace private var glassNS

    init(transaction: Transaction) {
        self.transaction = transaction
        _vm = State(wrappedValue: AddTransactionViewModel(
            defaultType: transaction.type,
            existingTransaction: transaction
        ))
    }

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            GlassEffectContainer(spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    categoryBubble
                    amountField
                }
            }

            GlassEffectContainer(spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    dateChip
                    noteField
                }
            }

            Spacer()

            GlassEffectContainer(spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    deleteButton
                    saveButton
                }
            }
        }
        .padding(DSSpacing.screenEdge)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onAppear {
            vm.update(categories: categories, allTransactions: allTransactions)
            vm.loadExisting(transaction)
        }
        .alert("Delete Transaction?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                do {
                    try vm.deleteTransaction(context: modelContext)
                    dismiss()
                } catch {
                    saveErrorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred. Please try again.")
        }
    }

    // MARK: - Category bubble

    private var categoryBubble: some View {
        Menu {
            ForEach(vm.filteredCategories) { cat in
                Button {
                    vm.selectedCategory = cat
                } label: {
                    if vm.selectedCategory?.id == cat.id {
                        Label("\(cat.emoji)  \(cat.name)", systemImage: "checkmark")
                    } else {
                        Text("\(cat.emoji)  \(cat.name)")
                    }
                }
            }
        } label: {
            Group {
                if let cat = vm.selectedCategory {
                    Text(cat.emoji).font(.dsTitle)
                } else {
                    Image(systemName: "tag")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("category", in: glassNS)
        }
        .accessibilityLabel(vm.selectedCategory.map { "Category: \($0.name)" } ?? "Pick a category")
    }

    // MARK: - Amount field

    private var amountField: some View {
        ZStack(alignment: .leading) {
            if vm.amountText.isEmpty {
                Text("Amount")
                    .font(.dsTitle)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            } else {
                Text(vm.formattedAmountDisplay)
                    .font(.dsTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: vm.formattedAmountDisplay)
                    .allowsHitTesting(false)
            }
            TextField("", text: $vm.amountText)
                .font(.dsTitle)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
        }
        .padding(.horizontal, DSSpacing.lg)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("amount", in: glassNS)
    }

    // MARK: - Date chip

    private var dateChip: some View {
        Menu {
            Button("Today") { vm.selectedDate = .now }
            Button("Yesterday") {
                vm.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            }
            DatePicker("Other", selection: $vm.selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(vm.dateChipLabel)
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textMuted)
            }
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("date", in: glassNS)
        }
    }

    // MARK: - Note field

    private var noteField: some View {
        TextField("Note", text: $vm.descriptionText)
            .font(.dsBody)
            .foregroundStyle(DSColor.textPrimary)
            .tint(DSColor.accent)
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("note", in: glassNS)
    }

    // MARK: - Delete + Save

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Image(systemName: "trash")
                .font(.dsBodyBold)
                .foregroundStyle(DSColor.negative)
                .frame(width: 50, height: 50)
                .glassEffect(.regular.tint(DSColor.negative.opacity(0.22)).interactive(), in: .circle)
                .glassEffectID("delete", in: glassNS)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete transaction")
    }

    private var saveButton: some View {
        Button {
            do {
                if try vm.save(context: modelContext) {
                    dismiss()
                }
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "checkmark")
                    .font(.dsBodyBold)
                Text("Save")
                    .font(.dsHeadline)
            }
            .foregroundStyle(vm.isValid ? DSColor.textOnAccent : DSColor.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .glassEffect(
                vm.isValid ? .regular.tint(DSColor.accent).interactive() : .regular,
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .disabled(!vm.isValid)
        .accessibilityLabel("Save transaction")
    }
}

#Preview {
    let tx = Transaction(amount: 50000, type: .expense, date: .now, note: "Coffee", category: nil, currencyCode: AppCurrency.code, tags: [])
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            EditTransactionSheet(transaction: tx)
                .modelContainer(SampleData.container())
        }
}
