import SwiftUI
import SwiftData

// MARK: - Shake effect
//
// Declarative horizontal shake for invalid-save feedback. Incrementing the
// trigger inside a single `withAnimation` drives `animatableData` from its
// old value to the new one; the `sin` curve turns that into a damped left-
// right wobble. Replaces a hand-timed sequence of four
// `DispatchQueue.main.asyncAfter` callbacks, which was prone to timing drift.
private struct ShakeEffect: GeometryEffect {
    /// Peak horizontal travel in points.
    var travel: CGFloat = 10
    /// Number of left-right oscillations per trigger.
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = travel * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

// MARK: - Per-character slot animation (mirrors Spendy CategorySlotView's SlotChar)
private struct SlotCharEffect: ViewModifier {
    let revealed: Bool
    let delay: Double
    var slideAmount: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .offset(y: revealed ? 0 : slideAmount)
            .opacity(revealed ? 1 : 0)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.72).delay(delay),
                value: revealed
            )
    }
}

// MARK: - Per-character fade-in label inside the sparkle pill
private struct SparkleCategoryLabel: View {
    let category: Category

    @State private var revealed = false

    private var charPairs: [(Int, String)] {
        Array(category.name).enumerated().map { ($0.offset + 1, String($0.element)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(category.emoji)
                .font(.dsSubhead)
                .modifier(SlotCharEffect(revealed: revealed, delay: 0.02, slideAmount: 10))
            Text(" ")
                .font(.dsSubhead)
            ForEach(charPairs, id: \.0) { idx, char in
                Text(char)
                    .font(.dsSubhead)
                    .modifier(SlotCharEffect(
                        revealed: revealed,
                        delay: Double(idx) * 0.016 + 0.04,
                        slideAmount: 10
                    ))
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { revealed = true }
        }
    }
}

// MARK: - Main View

struct AddTransactionView: View {
    // MARK: - Init
    let defaultType: TransactionType
    let existingTransaction: Transaction?

    init(defaultType: TransactionType = .expense,
         existingTransaction: Transaction? = nil) {
        self.defaultType = defaultType
        self.existingTransaction = existingTransaction
        _vm = State(wrappedValue: AddTransactionViewModel(
            defaultType: defaultType,
            existingTransaction: existingTransaction
        ))
    }

    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CategoryPredictor.self) private var predictor
    @Environment(AppearanceManager.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    // MARK: - VM
    @State private var vm: AddTransactionViewModel

    // MARK: - View-local state (UI / animation only)
    @State private var showCategoryPicker: Bool = false
    @State private var showDatePicker: Bool = false
    @State private var datePickerOpacity: Double = 0
    /// Incremented to trigger the invalid-save shake (see `ShakeEffect`).
    @State private var shakeTrigger: Int = 0
    /// Haptic triggers — incremented to fire `.sensoryFeedback`.
    @State private var saveSuccessCount = 0
    @State private var validationErrorCount = 0
    @State private var showDeleteAlert = false
    @State private var saveErrorMessage: String? = nil
    @State private var isTagInputActive: Bool = false
    /// Deferred insertion: tag TextField only joins the hierarchy on first use,
    /// avoiding RTI session churn on sheet present (verbatim Spendy comment).
    @State private var tagFieldInHierarchy: Bool = false

    enum FocusField { case description, amount }
    @FocusState private var focusedField: FocusField?
    @FocusState private var isTagFieldFocused: Bool

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            DSColor.bgGrouped.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, DSSpacing.screenEdge)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 18) {
                    metadataChips
                        .transaction { $0.animation = nil }

                    DatePicker("", selection: $vm.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: vm.selectedDate) { closeDatePicker() }
                        .frame(height: showDatePicker ? nil : 0)
                        .clipped()
                        .opacity(datePickerOpacity)

                    descriptionField
                    amountField
                    categoryArea
                }
                .padding(.horizontal, DSSpacing.screenEdge)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(nil, value: focusedField)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .safeAreaInset(edge: .bottom) { morphingBottomBar }
        .alert("Delete Transaction?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    do {
                        try vm.deleteTransaction(context: modelContext)
                    } catch {
                        saveErrorMessage = error.localizedDescription
                    }
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
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(selectedCategory: vm.selectedCategory) { picked in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    vm.selectedCategory = picked
                    vm.selectedType = picked.type
                    vm.isMLAssigned = false
                }
            }
        }
        .onAppear {
            vm.update(categories: categories, allTransactions: allTransactions)
            if let tx = existingTransaction {
                vm.loadExisting(tx)
                if !vm.selectedTags.isEmpty {
                    tagFieldInHierarchy = true
                    isTagInputActive = true
                }
            }
            // Keep focusedField in sync with the actual UIKit first responder
            // so other state (e.g. `.animation(nil, value: focusedField)` and
            // ML-prediction guard `focusedField == .description`) works as
            // expected. The actual `becomeFirstResponder()` call happens
            // inside AutoFocusTextField's `didMoveToWindow`, which fires
            // during the sheet's zoom present animation — that's what
            // delivers Mail-style keyboard timing. This assignment alone
            // wouldn't (SwiftUI's @FocusState → UIKit bridge runs too late).
            focusedField = .description
        }
        .onDisappear {
            focusedField = nil
            isTagFieldFocused = false
        }
        .onChange(of: categories) {
            vm.update(categories: categories, allTransactions: allTransactions)
        }
        .onChange(of: allTransactions) {
            vm.update(categories: categories, allTransactions: allTransactions)
        }
        .onChange(of: isTagFieldFocused) { _, focused in
            // Collapse back to State A when keyboard dismissed with no pending
            // input and no selected tags.
            if !focused && vm.tagInput.isEmpty && vm.selectedTags.isEmpty {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isTagInputActive = false
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveSuccessCount)
        .sensoryFeedback(.error, trigger: validationErrorCount)
        // Always pass a concrete scheme — `effectiveScheme` resolves `.system`
        // to the live OS scheme tracked by AppearanceManager via UIScreen.
        // See SettingsView for the full rationale (nil-doesn't-reset bug +
        // view-structure changes popping navigation).
        .preferredColorScheme(appearance.effectiveScheme)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            if existingTransaction != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .tint(.red)
                .accessibilityLabel("Delete transaction")
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .tint(.primary)
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: - Metadata Chips
    private var metadataChips: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Button(type.displayName) { vm.changeType(type) }
                }
            } label: {
                chipLabel(vm.selectedType.displayName)
            }
            .menuStyle(.button).buttonStyle(.plain)

            Menu {
                Button("Today") {
                    vm.selectedDate = .now
                    if showDatePicker { closeDatePicker() }
                }
                Button("Yesterday") {
                    vm.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                    if showDatePicker { closeDatePicker() }
                }
                Button("Other…") {
                    focusedField = nil
                    withAnimation(.easeInOut(duration: 0.32)) { showDatePicker = true }
                    withAnimation(.easeIn(duration: 0.2).delay(0.1)) { datePickerOpacity = 1 }
                }
            } label: {
                chipLabel(vm.dateChipLabel)
            }
            .menuStyle(.button).buttonStyle(.plain)

            Spacer()
        }
    }

    private func chipLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.dsCaption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.dsBadge)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color(.separator), lineWidth: 0.5))
        .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: 999))
    }

    // MARK: - Text Fields
    //
    // Description uses a UIKit-backed AutoFocusTextField (UIViewRepresentable)
    // so the first-responder claim fires inside `didMoveToWindow` — i.e.
    // *during* the sheet's zoom present animation. SwiftUI's `TextField`
    // + `@FocusState` couldn't deliver Mail-style timing because the
    // FocusState → becomeFirstResponder bridge runs on a later runloop tick,
    // so the keyboard slide happened sequentially after the zoom finished.
    private var descriptionField: some View {
        AutoFocusTextField(
            text: $vm.descriptionText,
            placeholder: "Description",
            font: UIFont.systemFont(ofSize: 34, weight: .bold),  // mirrors DSFont.dsTitle
            focusBinding: $focusedField,
            focusValue: FocusField.description,
            autoFocusOnAppear: true,
            returnKeyType: .next,
            onChange: { newValue in handleDescriptionChange(newValue) },
            onSubmit: {
                // NLP commit: split "5 dollar for coffee" → amount 5 (USD) +
                // note "coffee" + ML category, then move on to the amount field.
                vm.applyParsedDescription(predictor: predictor)
                focusedField = .amount
            }
        )
        // Match the original frame so layout stays the same.
        .frame(height: 44)
    }

    /// Pulled out of the .onChange closure so the descriptionField var stays
    /// compact and the closure can capture state cleanly across the UIKit
    /// bridge. Logic preserved verbatim from the SwiftUI version.
    private func handleDescriptionChange(_ newValue: String) {
        // Only run ML when the user is actively typing.
        // When editing an existing transaction, loadExisting() seeds
        // descriptionText programmatically during onAppear with no focus —
        // skip ML so we don't overwrite the saved category.
        guard existingTransaction == nil || focusedField == .description else { return }

        if newValue.isEmpty {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                if vm.isMLAssigned { vm.selectedCategory = nil }
                vm.isMLAssigned = false
            }
            vm.latestMLCategory = nil
            vm.cancelMLPrediction()
        } else {
            // NOTE: a negative correction (actual: nil) is intentionally NOT
            // logged here. Firing on every keystroke/backspace over-weighted
            // negative signals and degraded the model over time. Negative
            // corrections are logged only on explicit deselect of an ML-picked
            // category — see `sparkleButton`.
            vm.triggerMLPrediction(note: newValue, predictor: predictor)
        }
    }

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
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: vm.formattedAmountDisplay)
                    .allowsHitTesting(false)
            }
            TextField("", text: $vm.amountText)
                .font(.dsTitle)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .amount)
                .foregroundStyle(.clear)
                .tint(.clear)
        }
        .overlay(alignment: .bottomLeading) {
            Text("IDR")
                .font(.dsBadge)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .offset(y: -46)
                .opacity(vm.amountText.isEmpty ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: vm.amountText.isEmpty)
        }
    }

    // MARK: - Category Area
    private var categoryArea: some View {
        HStack(spacing: 8) {
            sparkleButton

            if vm.selectedCategory == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.filteredCategories) { cat in
                            Button {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                    vm.selectedCategory = cat
                                    vm.isMLAssigned = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(cat.emoji).font(.dsSubhead)
                                    Text(cat.name)
                                        .font(.dsBodyMedium)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: 999))
                                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color(.separator), lineWidth: 0.5))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 1)],
                            startPoint: .leading, endPoint: .trailing
                        ).frame(width: 16)
                        Rectangle()
                        LinearGradient(
                            stops: [.init(color: .black, location: 0), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing
                        ).frame(width: 28)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(height: 44)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: vm.selectedCategory?.id)
    }

    @ViewBuilder
    private var sparkleButton: some View {
        Button {
            if vm.selectedCategory != nil {
                // If we're discarding an ML-assigned category, that's a
                // negative correction signal for training.
                if vm.isMLAssigned, let predicted = vm.latestMLCategory {
                    predictor.logCorrection(
                        note: vm.descriptionText,
                        amount: vm.parsedAmount,
                        predicted: predicted.name,
                        actual: nil
                    )
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    vm.selectedCategory = nil
                    vm.isMLAssigned = false
                    vm.latestMLCategory = nil
                }
            } else {
                showCategoryPicker = true
            }
        } label: {
            HStack(spacing: 0) {
                if vm.selectedCategory == nil || vm.isMLAssigned {
                    Image(systemName: "sparkles")
                        .font(.system(size: vm.selectedCategory != nil ? 13 : 17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(
                            .variableColor.iterative.reversing,
                            options: .repeating.speed(0.4),
                            // Suppress the continuous pulse under Reduce Motion (AC5).
                            isActive: !reduceMotion && vm.sparkleActive && vm.selectedCategory == nil
                        )
                        .foregroundStyle(
                            vm.selectedCategory != nil ? .white :
                            vm.sparkleActive ? .white :
                            DSColor.accent
                        )
                        .frame(width: vm.selectedCategory != nil ? 28 : 40, height: 40)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: vm.selectedCategory != nil)
                }
                if let cat = vm.selectedCategory {
                    SparkleCategoryLabel(category: cat)
                        .id(cat.id)
                        .padding(.leading, vm.isMLAssigned ? 0 : 14)
                        .padding(.trailing, 14)
                }
            }
            .frame(height: 40)
            .background(
                vm.sparkleActive || vm.selectedCategory != nil ? DSColor.accent : DSColor.bgCard,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    Color(.separator),
                    lineWidth: vm.sparkleActive || vm.selectedCategory != nil ? 0 : 0.5
                )
            )
        }
        .buttonStyle(.pressable)
        .allowsHitTesting(vm.sparkleActive || vm.selectedCategory != nil)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: vm.selectedCategory?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: vm.sparkleActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: vm.isMLAssigned)
    }

    // MARK: - Save (shared action)
    private func performSave() {
        do {
            if try vm.save(context: modelContext) {
                // If the user overrode the ML suggestion with a different
                // category before saving, log a positive correction.
                if let mlPick = vm.latestMLCategory,
                   let final = vm.selectedCategory,
                   !vm.isMLAssigned, mlPick.id != final.id {
                    predictor.logCorrection(
                        note: vm.descriptionText,
                        amount: vm.parsedAmount,
                        predicted: mlPick.name,
                        actual: final.name
                    )
                }
                // Background train using the now-updated transaction set.
                // Training is gated internally (≥20 transactions, +10 since last).
                predictor.trainIfReady(transactions: vm.trainableSnapshots())
                saveSuccessCount += 1
                dismiss()
            } else {
                triggerShake()
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Morphing Bottom Bar
    private var morphingBottomBar: some View {
        HStack(spacing: 10) {
            // Left: Tag Pill — grows to fill when active
            tagInputPill
                .frame(maxWidth: isTagInputActive ? .infinity : 50)
                .background(DSColor.bgCard, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                .clipped()

            // Right: Save Button — shrinks to circle when tag editor is active
            Button(action: performSave) {
                HStack(spacing: isTagInputActive ? 0 : 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: isTagInputActive ? 17 : 15, weight: .semibold))

                    // Keep in hierarchy to avoid layout rebuild mid-spring;
                    // collapse with opacity + zero-width instead of if/else removal.
                    Text("Save")
                        .font(.dsHeadline)
                        .opacity(isTagInputActive ? 0 : 1)
                        .frame(maxWidth: isTagInputActive ? 0 : nil, alignment: .leading)
                        .clipped()
                        .animation(.easeOut(duration: 0.18), value: isTagInputActive)
                }
                .foregroundStyle(DSColor.bgPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .clipped()
            }
            .opacity(vm.isValid ? 1.0 : 0.45)
            .disabled(!vm.isValid)
            .accessibilityLabel("Save transaction")
            .frame(maxWidth: isTagInputActive ? 50 : .infinity)
            .frame(height: 50)
            .background(Color.primary, in: Capsule())
        }
        .frame(height: 50)
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.bottom, 8)
        .background(DSColor.bgGrouped)
    }

    // MARK: - Tag Input Pill
    private var tagInputPill: some View {
        ZStack(alignment: .leading) {

            // ── Inactive state: "#" icon ────────────────────────────────────
            Button {
                tagFieldInHierarchy = true
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isTagInputActive = true
                }
                DispatchQueue.main.async {
                    isTagFieldFocused = true
                }
            } label: {
                Text("#")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
            }
            .accessibilityLabel("Add tags")
            .opacity(isTagInputActive ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: isTagInputActive)
            .allowsHitTesting(!isTagInputActive)

            // ── Active state: close + tags + text field ─────────────────────
            if tagFieldInHierarchy {
                HStack(spacing: 0) {
                    Button {
                        isTagFieldFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isTagInputActive = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(DSColor.bgGrouped, in: Circle())
                    }
                    .padding(.leading, 8)
                    .accessibilityLabel("Close tag editor")

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(vm.selectedTags, id: \.self) { tag in
                                    HStack(spacing: 3) {
                                        Text("#\(tag)")
                                            .font(.dsCaption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(DSColor.accent)
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                vm.removeTag(tag)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.dsBadge)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(DSColor.accent.opacity(0.8))
                                        }
                                        .accessibilityLabel("Remove \(tag) tag")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DSColor.accent.opacity(DSOpacity.subtle), in: Capsule())
                                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                                    .id(tag)
                                }

                                ZStack(alignment: .leading) {
                                    HStack(spacing: 0) {
                                        Text(vm.tagInput)
                                            .font(.dsCaption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.clear)
                                        Text(vm.shadowSuggestion)
                                            .font(.dsCaption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                    .allowsHitTesting(false)

                                    TextField("", text: $vm.tagInput,
                                              prompt: Text(vm.selectedTags.isEmpty ? "Add tags…" : "More tags…")
                                                  .foregroundStyle(.secondary))
                                        .font(.dsCaption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .submitLabel(.done)
                                        .focused($isTagFieldFocused)
                                        .frame(minWidth: 90, alignment: .leading)
                                        .onSubmit {
                                            vm.commitTag(context: modelContext)
                                            isTagFieldFocused = true
                                        }
                                        .onChange(of: vm.tagInput) { _, newValue in
                                            if newValue.last == " " {
                                                vm.tagInput = String(newValue.dropLast())
                                                vm.commitTag(context: modelContext)
                                            }
                                        }
                                }
                                .id("textField")
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .frame(height: 50)
                        }
                        .onChange(of: vm.selectedTags.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("textField", anchor: .trailing)
                            }
                        }
                    }
                    .onTapGesture { isTagFieldFocused = true }
                }
                .opacity(isTagInputActive ? 1 : 0)
                .animation(
                    isTagInputActive
                        ? .easeIn(duration: 0.18).delay(0.08)
                        : .easeOut(duration: 0.12),
                    value: isTagInputActive
                )
                .allowsHitTesting(isTagInputActive)
            }
        }
        .frame(height: 50)
    }

    // MARK: - Animation helpers

    private func closeDatePicker() {
        withAnimation(.easeOut(duration: 0.18)) { datePickerOpacity = 0 }
        withAnimation(.easeInOut(duration: 0.32)) { showDatePicker = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            focusedField = .description
        }
    }

    private func triggerShake() {
        validationErrorCount += 1
        // Reduce Motion users still get the error haptic (validationErrorCount),
        // but skip the horizontal shake animation (AC5).
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.4)) { shakeTrigger += 1 }
    }
}

#Preview {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            AddTransactionView(defaultType: .expense)
                .modelContainer(SampleData.container())
                .environment(CategoryPredictor())
                .environment(AppearanceManager())
        }
}
