import SwiftUI
import SwiftData
import UIKit

/// Experimental Messages-style inline composer (Phase 8.5 / V3), rendered in
/// **Liquid Glass** (iOS 26 `glassEffect`). A capsule field + leading category
/// bubble + trailing send button, with the parsed result surfacing as its own
/// centered glass bubble above the field. Lives in a `.safeAreaInset(.bottom)`
/// so it rides the keyboard; it is not a sheet.
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
    /// Closes the composer (also called on save).
    var onDismiss: () -> Void = {}

    private var expenseCategories: [Category] {
        allCategories.filter { $0.type == .expense }
    }

    var body: some View {
        GlassEffectContainer(spacing: DSSpacing.sm) {
            VStack(spacing: DSSpacing.sm) {
                if let result = vm.parseResult {
                    summaryBubble(result)
                        // Appears from below; on save it shrinks + flies up
                        // toward the transaction list ("expand to list").
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .move(edge: .top)
                                .combined(with: .scale(scale: 0.5, anchor: .top))
                                .combined(with: .opacity)
                        ))
                }

                HStack(spacing: DSSpacing.sm) {
                    categoryBubble
                    textField
                    sendButton
                }
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.vertical, DSSpacing.sm)
        .animation(.dsSnappy, value: vm.parseResult)
        .sensoryFeedback(.success, trigger: sendCount)
        .task {
            // Focus immediately so the keyboard starts rising in the same beat as
            // the composer appears — the composer then rides up *with* the
            // keyboard (one motion) rather than sliding up first and being pushed
            // again 250ms later.
            focused = true
        }
    }

    // MARK: - Parsed-result bubble (Liquid Glass, centered, above the field)

    private func summaryBubble(_ result: ParsedInlineTransaction) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(dateLabel(result.date))
                .foregroundStyle(DSColor.textSecondary)
            if let note = result.note, !note.isEmpty {
                dot
                Text(note)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
            }
            dot
            Text(result.amount.rupiah)
                .fontWeight(.semibold)
                .foregroundStyle(DSColor.textPrimary)
        }
        .font(.dsCaption)
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

    // MARK: - Category bubble (Liquid Glass circle)

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
            .tint(DSColor.accent)
            .focused($focused)
            .submitLabel(.send)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: vm.inputText) {
                vm.scheduleParse(categories: allCategories, predictor: predictor)
            }
            // Return sends when armed, otherwise just closes the composer (so the
            // return key never leaves a stranded empty bar behind the keyboard).
            .onSubmit {
                if vm.canSend { send() } else { onDismiss() }
            }
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("field", in: glassNS)
    }

    // MARK: - Send button (Liquid Glass circle, accent-tinted when armed)

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.dsBodyBold)
                .foregroundStyle(vm.canSend ? DSColor.textOnAccent : DSColor.textMuted)
                .frame(width: 44, height: 44)
                .glassEffect(
                    vm.canSend ? .regular.tint(DSColor.accent).interactive() : .regular,
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
        guard let tx = vm.save(context: modelContext) else { return }  // resets → bubble flies up
        sendCount += 1
        onTransactionCreated(tx)
        // Let the bubble shrink-and-fly-up play, then close. `onDismiss` removes
        // the composer, which dismisses the keyboard — so the bar and keyboard
        // slide down together (no separate `focused = false` beat).
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            onDismiss()
        }
    }
}

// MARK: - Host modifier (rides the keyboard via a bottom safe-area inset)

/// Applies the inline composer to a Today view as a keyboard-riding bottom bar
/// when `vm.showInlineComposer` is set. Tapping the content above the composer
/// dismisses it (there's no grabber); saving also dismisses it.
struct InlineComposerModifier: ViewModifier {
    @Bindable var vm: TodayViewModel

    func body(content: Content) -> some View {
        content
            // Tap-catcher over the content above the composer — tap to dismiss.
            // Applied before the inset so it only covers the list, not the bar.
            .overlay {
                if vm.showInlineComposer {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss() }
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if vm.showInlineComposer {
                    // Zoom out of / shrink back into the bottom-trailing corner —
                    // where the `+` toolbar button sits — to echo V1's sheet
                    // zoom from the add button. No vertical *move* (that comes
                    // from the keyboard lifting the safe-area inset), so the bar
                    // still rides up/down with the keyboard while it scales.
                    InlineTransactionEntryView(onDismiss: dismiss)
                        .transition(
                            .scale(scale: 0.2, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                }
            }
            .animation(.dsSnappy, value: vm.showInlineComposer)
    }

    /// Close in sync with the keyboard: resign first responder so the keyboard
    /// descends and the safe-area-inset bar rides *down with it*, then remove the
    /// bar once it's down. Removing it immediately (the old behavior) left it
    /// fading in place up top while the keyboard slid away — the close stagger.
    private func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            vm.showInlineComposer = false
        }
    }
}

extension View {
    func inlineComposer(vm: TodayViewModel) -> some View {
        modifier(InlineComposerModifier(vm: vm))
    }
}
