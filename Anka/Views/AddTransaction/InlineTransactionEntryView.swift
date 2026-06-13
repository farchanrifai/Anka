import SwiftUI
import SwiftData

/// Shared layout constants so the sheet detent and the composer content agree.
enum InlineComposerMetrics {
    /// Sheet height: bubble/field row (44) + the optional summary line + padding.
    static let sheetHeight: CGFloat = 128
}

/// Experimental Messages-style inline composer (Phase 8.5 / V3). A compact bar —
/// category bubble · natural-language field · send — presented as a short sheet
/// so it rides above the keyboard while the transaction list stays visible and
/// interactive behind it. Type e.g. "5k coffee" or "100k grabfood yesterday".
struct InlineTransactionEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CategoryPredictor.self) private var predictor
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var vm = InlineTransactionEntryViewModel()
    @State private var sendCount = 0
    @FocusState private var focused: Bool

    /// Called after each successful save with the created transaction, so the
    /// host can react (e.g. scroll the list). The list animation itself is
    /// handled centrally by the `.ankaDataDidChange` refresh.
    var onTransactionCreated: (Transaction) -> Void = { _ in }

    private var expenseCategories: [Category] {
        allCategories.filter { $0.type == .expense }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let result = vm.parseResult {
                summaryLine(result)
                    .transition(.opacity)
            }

            HStack(spacing: DSSpacing.sm) {
                categoryBubble
                textField
                sendButton
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.top, DSSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.dsSnappy, value: vm.parseResult)
        .sensoryFeedback(.success, trigger: sendCount)
        .task {
            // Auto-focus so the keyboard rises with the composer.
            try? await Task.sleep(for: .milliseconds(250))
            focused = true
        }
    }

    // MARK: - Summary

    private func summaryLine(_ result: ParsedInlineTransaction) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(result.amount.rupiah)
                .font(.dsCaptionSemi)
                .foregroundStyle(DSColor.textPrimary)
            Text("·")
                .foregroundStyle(DSColor.textMuted)
            Text(dateLabel(result.date))
                .font(.dsCaption)
                .foregroundStyle(DSColor.textSecondary)
            if let cat = vm.effectiveCategory {
                Text("·")
                    .foregroundStyle(DSColor.textMuted)
                Text("\(cat.emoji) \(cat.name)")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.monthYearLabel == Date().monthYearLabel
            ? date.relativeLabel
            : date.fullDateLabel
    }

    // MARK: - Category bubble

    private var categoryBubble: some View {
        Menu {
            ForEach(expenseCategories) { cat in
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
            if vm.selectedCategory != nil {
                Divider()
                Button("Auto-detect", systemImage: "sparkles") {
                    vm.selectedCategory = nil
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(bubbleFill)
                    .frame(width: 44, height: 44)
                if let cat = vm.effectiveCategory {
                    Text(cat.emoji)
                        .font(.dsTitle3)
                } else {
                    Image(systemName: "tag")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textMuted)
                }
            }
        }
        .accessibilityLabel(vm.effectiveCategory.map { "Category: \($0.name)" } ?? "Pick a category")
    }

    private var bubbleFill: Color {
        if let cat = vm.effectiveCategory {
            return Color(hex: cat.colorHex).opacity(DSOpacity.subtle)
        }
        return DSColor.bgSecondary
    }

    // MARK: - Text field

    private var textField: some View {
        TextField("5k for coffee", text: $vm.inputText)
            .font(.dsBody)
            .foregroundStyle(DSColor.textPrimary)
            .focused($focused)
            .submitLabel(.send)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: vm.inputText) {
                vm.scheduleParse(categories: allCategories, predictor: predictor)
            }
            .onSubmit(send)
            .padding(.horizontal, DSSpacing.md)
            .frame(height: 44)
            .background(DSColor.bgSecondary, in: Capsule())
    }

    // MARK: - Send

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.dsBodyBold)
                .foregroundStyle(DSColor.textOnAccent)
                .frame(width: 44, height: 44)
                .background(vm.canSend ? DSColor.accent : DSColor.bgSecondary, in: Circle())
                .opacity(vm.canSend ? 1 : 0.6)
        }
        .disabled(!vm.canSend)
        .accessibilityLabel("Add transaction")
    }

    private func send() {
        guard vm.canSend else { return }
        guard let tx = vm.save(context: modelContext) else { return }
        sendCount += 1
        onTransactionCreated(tx)
        // Keep focus for the next quick entry.
        focused = true
    }
}
