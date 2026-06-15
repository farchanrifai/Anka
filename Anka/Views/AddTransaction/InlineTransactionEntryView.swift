import SwiftUI
import SwiftData

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
    @Namespace private var glassNS
    // The summary bubble gets its OWN namespace, separate from the composer
    // row's (`glassNS`). `glassEffectID(_, in:)` groups shapes into a shared
    // "merge group" for Liquid Glass's blob-fusion rendering — when the
    // summary bubble shared `glassNS` with the row's bubbles, every
    // appearance/disappearance of the summary bubble made the row's glass
    // shapes recompute their fusion geometry too, which is what was causing
    // the row to visibly jump/reset.
    @Namespace private var summaryGlassNS
    /// User preference: close the composer after sending vs. keep it open.
    @AppStorage(InlineComposerPrefs.saveClosesKey) private var saveClosesComposer = true

    /// Focus binding owned by the **host** (`InlineComposerModifier`) so the
    /// keyboard state survives this view being torn down / reused on a rapid
    /// close→reopen — the keyboard then follows the field's presence + this one
    /// focus set, with no fragile re-assert toggling.
    var focus: FocusState<Bool>.Binding
    /// Called after each successful save with the created transaction.
    var onTransactionCreated: (Transaction) -> Void = { _ in }
    /// Closes the composer (also called on save).
    var onDismiss: () -> Void = {}

    private var expenseCategories: [Category] {
        allCategories.filter { $0.type == .expense }
    }

    /// Height reserved for the summary bubble's row (its own height + the
    /// gap above the composer row), used to give the `ZStack` below a
    /// CONSTANT total height whether or not the summary bubble is showing.
    /// Without this, the `ZStack`'s natural height changes from 44pt to
    /// ~88pt when the bubble appears, which resizes the `safeAreaInset` that
    /// hosts this view — THAT resize, not glass-effect recomputation, is what
    /// was shifting the composer row each time the bubble appeared.
    private static let summaryRowHeight: CGFloat = 44

    var body: some View {
        // `.bottom`-aligned ZStack so the summary bubble overlays *above* the
        // composer row via bottom padding, instead of being a sibling that
        // changes the stack's height. The whole stack is then pinned to a
        // fixed height (see `summaryRowHeight`) so its size — and therefore
        // the `safeAreaInset` that hosts it — never changes, regardless of
        // whether the summary bubble is present.
        ZStack(alignment: .bottom) {
            if let result = vm.parseResult {
                GlassEffectContainer(spacing: DSSpacing.sm) {
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
                // Lift above the composer row (its height + the stack's
                // own inter-row spacing).
                .padding(.bottom, 44 + DSSpacing.sm)
            }

            GlassEffectContainer(spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    categoryBubble
                    textField
                    sendButton
                }
            }
        }
        .frame(height: 44 + DSSpacing.sm + Self.summaryRowHeight, alignment: .bottom)
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.vertical, DSSpacing.sm)
        .animation(.dsSnappy, value: vm.parseResult)
        .sensoryFeedback(.success, trigger: sendCount)
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
        .glassEffectID("summary", in: summaryGlassNS)
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
            .focused(focus)
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
            .glassEffect(.regular.interactive(), in: .capsule)
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
        .buttonStyle(.plain)
        .disabled(!vm.canSend)
        .accessibilityLabel("Add transaction")
    }

    // MARK: - Actions

    private func send() {
        guard vm.canSend else { return }
        guard let tx = vm.save(context: modelContext) else { return }  // resets → bubble flies up
        sendCount += 1
        onTransactionCreated(tx)
        guard saveClosesComposer else {
            // Keep the composer open for the next entry. Sending via the
            // keyboard's return/send key can resign the field's focus as
            // part of the submit (unlike tapping the in-composer send
            // button), which would leave the bar open but the keyboard
            // closed. Re-assert focus so the keyboard always stays up while
            // the composer is visible, regardless of how send was triggered.
            focus.wrappedValue = true
            return
        }
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
    /// Owned here (not in the bar view) so it isn't reset when the bar is torn
    /// down/reused on a rapid close→reopen — that reuse is exactly what made the
    /// keyboard fail to appear, and the recovery toggle that "fixed" it caused
    /// the open/close flicker. The keyboard now follows the field's presence plus
    /// this one focus set per open: no toggling, no flicker.
    @FocusState private var composerFocused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: vm.showInlineComposer) { _, isOpen in
                guard isOpen else { return }
                // Defer one runloop so the field is mounted, then focus it.
                Task { @MainActor in composerFocused = true }
            }
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
                    // Open: plain opacity (no zoom) — the bar just fades in while
                    // the keyboard lifts the safe-area inset.
                    // Close: shrink back into the bottom-trailing corner (where
                    // the `+` sits). Asymmetric so only the close zooms.
                    InlineTransactionEntryView(focus: $composerFocused, onDismiss: dismiss)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.2, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        ))
                }
            }
            // Open/close are animated explicitly (snappy open, slower smooth
            // close) rather than via one implicit `.animation`, so the two can
            // differ — see `dismiss()` and `AddToolbarButton`.
    }

    /// Close: drop focus (the keyboard starts sliding down) and shrink the bar at
    /// the same time, at a gentler search-bar pace. Removing the field would also
    /// dismiss the keyboard, but clearing `composerFocused` keeps the host's
    /// focus state honest for the next open.
    private func dismiss() {
        composerFocused = false
        withAnimation(.smooth(duration: 0.4)) {
            vm.showInlineComposer = false
        }
    }
}

extension View {
    func inlineComposer(vm: TodayViewModel) -> some View {
        modifier(InlineComposerModifier(vm: vm))
    }
}
