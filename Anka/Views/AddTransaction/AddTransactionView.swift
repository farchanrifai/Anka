import SwiftUI
import SwiftData

// ShakeEffect / SlotCharEffect / SparkleCategoryLabel live in
// Components/Effects.swift; the bottom bar + sparkle pill in
// MorphingBottomBar.swift.

// MARK: - Main View

struct AddTransactionView: View {
    // MARK: - Init
    // Add-only: editing goes through the compact EditTransactionSheet.
    let defaultType: TransactionType

    init(defaultType: TransactionType = .expense) {
        self.defaultType = defaultType
        _vm = State(wrappedValue: AddTransactionViewModel(defaultType: defaultType))
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

                    if showDatePicker {
                        DatePicker("", selection: $vm.selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .onChange(of: vm.selectedDate) { closeDatePicker() }
                            .clipped()
                            .opacity(datePickerOpacity)
                    }

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
        .safeAreaInset(edge: .bottom) {
            MorphingBottomBar(
                vm: vm,
                isTagInputActive: $isTagInputActive,
                tagFieldInHierarchy: $tagFieldInHierarchy,
                isTagFieldFocused: $isTagFieldFocused,
                onSave: performSave
            )
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
                withAnimation(.dsMorph) {
                    vm.selectedCategory = picked
                    vm.selectedType = picked.type
                    vm.isMLAssigned = false
                }
            }
        }
        .onAppear {
            vm.update(categories: categories, allTransactions: allTransactions)
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
                withAnimation(.dsSpringSoft) {
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
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.dsFootnoteSemi)
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
        .dsChip()
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
        if newValue.isEmpty {
            withAnimation(.dsMorph) {
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
                    .animation(.dsSnappyFast, value: vm.formattedAmountDisplay)
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
            SparkleCategoryButton(vm: vm, showCategoryPicker: $showCategoryPicker)

            if vm.selectedCategory == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.filteredCategories) { cat in
                            Button {
                                withAnimation(.dsMorph) {
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
                                .dsChip()
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
        .animation(.dsMorph, value: vm.selectedCategory?.id)
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

    // MARK: - Animation helpers

    private func closeDatePicker() {
        withAnimation(.easeOut(duration: 0.18)) { datePickerOpacity = 0 }
        // Drive focus off the animation's completion instead of a hand-tuned
        // `asyncAfter(0.38)` that could drift out of sync with the animation
        // (AN3 — the same fragile pattern the file's ShakeEffect comment removed).
        withAnimation(.easeInOut(duration: 0.32)) {
            showDatePicker = false
        } completion: {
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
