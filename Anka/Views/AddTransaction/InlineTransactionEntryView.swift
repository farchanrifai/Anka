import SwiftUI
import SwiftData

/// Experimental Messages-style inline composer (Phase 8.5 / V3), rendered in
/// **Liquid Glass** (iOS 26 `glassEffect`). A capsule field + leading category
/// bubble + trailing send button, with the parsed result surfacing as its own
/// glass bubble above the field — the same material as the system search bar /
/// Messages composer. Lives in a `.safeAreaInset(.bottom)` so it rides the
/// keyboard; it is not a sheet.
struct InlineTransactionEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CategoryPredictor.self) private var predictor
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var vm = InlineTransactionEntryViewModel()
    @State private var sendCount = 0
    @FocusState private var focused: Bool
    @Namespace private var glassNS

    /// Called after each successful save with the created transaction.
    var onTransactionCreated: (Transaction) -> Void = { _ in }
    /// Called to close the composer (e.g. the chevron).
    var onDismiss: () -> Void = {}

    /// Messages-style send blue. No DS blue token exists; this is the single
    /// place it's used, matching the system composer's accent.
    private let sendBlue = Color(red: 0.0, green: 0.48, blue: 1.0)

    private var expenseCategories: [Category] {
        allCategories.filter { $0.type == .expense }
    }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            grabber
            GlassEffectContainer(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    if let result = vm.parseResult {
                        summaryBubble(result)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    HStack(spacing: DSSpacing.sm) {
                        categoryBubble
                        textField
                        sendButton
                    }
                }
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.sm)
        .animation(.dsSnappy, value: vm.parseResult)
        .sensoryFeedback(.success, trigger: sendCount)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            focused = true
        }
    }

    /// Drag-indicator handle: tap or swipe-down to close the composer. Kept off
    /// the text field so it doesn't fight the field's own selection gestures.
    private var grabber: some View {
        Capsule()
            .fill(DSColor.textMuted.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.vertical, DSSpacing.xs)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { if $0.translation.height > 24 { dismiss() } }
            )
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
    }

    private func dismiss() {
        focused = false
        onDismiss()
    }

    // MARK: - Parsed-result bubble (Liquid Glass, above the field)

    private func summaryBubble(_ result: ParsedInlineTransaction) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(result.amount.rupiah)
                .font(.dsCaptionSemi)
                .foregroundStyle(DSColor.textPrimary)
            dot
            Text(dateLabel(result.date))
                .font(.dsCaption)
                .foregroundStyle(DSColor.textSecondary)
            if let cat = vm.effectiveCategory {
                dot
                Text("\(cat.emoji) \(cat.name)")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("summary", in: glassNS)
    }

    private var dot: some View {
        Text("·").foregroundStyle(DSColor.textMuted)
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.monthYearLabel == Date().monthYearLabel ? date.relativeLabel : date.fullDateLabel
    }

    // MARK: - Category bubble (Liquid Glass circle, like Messages "+")

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
                Button("Auto-detect", systemImage: "sparkles") { vm.selectedCategory = nil }
            }
        } label: {
            Group {
                if let cat = vm.effectiveCategory {
                    Text(cat.emoji).font(.dsTitle3)
                } else {
                    Image(systemName: "tag")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("category", in: glassNS)
        }
        .accessibilityLabel(vm.effectiveCategory.map { "Category: \($0.name)" } ?? "Pick a category")
    }

    // MARK: - Text field (Liquid Glass capsule, like the search bar)

    private var textField: some View {
        TextField("5k for coffee", text: $vm.inputText)
            .font(.dsBody)
            .foregroundStyle(DSColor.textPrimary)
            .tint(sendBlue)
            .focused($focused)
            .submitLabel(.send)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: vm.inputText) {
                vm.scheduleParse(categories: allCategories, predictor: predictor)
            }
            .onSubmit(send)
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("field", in: glassNS)
    }

    // MARK: - Send button (Liquid Glass circle, blue when armed)

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.dsBodyBold)
                .foregroundStyle(vm.canSend ? Color.white : DSColor.textMuted)
                .frame(width: 44, height: 44)
                .glassEffect(
                    vm.canSend ? .regular.tint(sendBlue).interactive() : .regular,
                    in: .circle
                )
                .glassEffectID("send", in: glassNS)
        }
        .disabled(!vm.canSend)
        .accessibilityLabel("Add transaction")
    }

    // MARK: - Actions

    private func send() {
        guard vm.canSend else { return }
        guard let tx = vm.save(context: modelContext) else { return }
        sendCount += 1
        onTransactionCreated(tx)
        focused = true   // keep the keyboard up for the next quick entry
    }
}

// MARK: - Host modifier (rides the keyboard via a bottom safe-area inset)

/// Applies the inline composer to a Today view as a keyboard-riding bottom bar
/// when `vm.showInlineComposer` is set — replacing the old sheet presentation.
struct InlineComposerModifier: ViewModifier {
    @Bindable var vm: TodayViewModel

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if vm.showInlineComposer {
                    InlineTransactionEntryView(onDismiss: { vm.showInlineComposer = false })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.dsSnappy, value: vm.showInlineComposer)
    }
}

extension View {
    func inlineComposer(vm: TodayViewModel) -> some View {
        modifier(InlineComposerModifier(vm: vm))
    }
}
