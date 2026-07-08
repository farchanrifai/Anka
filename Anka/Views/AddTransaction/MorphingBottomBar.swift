import SwiftUI
import SwiftData

// MARK: - Morphing bottom bar
//
// The Add sheet's bottom bar: a tag pill that grows from a 50pt "#" circle to
// full width while the Save button shrinks to a circle. Extracted from
// AddTransactionView (which owns the driving state and the save action).
struct MorphingBottomBar: View {
    @Bindable var vm: AddTransactionViewModel
    @Binding var isTagInputActive: Bool
    /// Deferred insertion: tag TextField only joins the hierarchy on first use,
    /// avoiding RTI session churn on sheet present (verbatim Spendy comment).
    @Binding var tagFieldInHierarchy: Bool
    var isTagFieldFocused: FocusState<Bool>.Binding
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 10) {
            // Left: Tag Pill — grows to fill when active
            tagInputPill
                .frame(maxWidth: isTagInputActive ? .infinity : 50)
                .background(DSColor.bgCard, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                .clipped()

            // Right: Save Button — shrinks to circle when tag editor is active
            Button(action: onSave) {
                HStack(spacing: isTagInputActive ? 0 : 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: isTagInputActive ? 17 : 15, weight: .semibold, relativeTo: .body))

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
                withAnimation(.dsSpringSoft) {
                    isTagInputActive = true
                }
                DispatchQueue.main.async {
                    isTagFieldFocused.wrappedValue = true
                }
            } label: {
                Text("#")
                    .font(.system(size: 20, weight: .bold, relativeTo: .title3))
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
                        isTagFieldFocused.wrappedValue = false
                        withAnimation(.dsSpringSoft) {
                            isTagInputActive = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.dsFootnoteBold)
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
                                            withAnimation(.dsSpring) {
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
                                        .focused(isTagFieldFocused)
                                        .frame(minWidth: 90, alignment: .leading)
                                        .onSubmit {
                                            vm.commitTag(context: modelContext)
                                            isTagFieldFocused.wrappedValue = true
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
                    .onTapGesture { isTagFieldFocused.wrappedValue = true }
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
}

// MARK: - Sparkle / category button
//
// The ML category pill: sparkles icon when idle/predicting, morphs into the
// coral category label when a category is picked. Tapping a picked category
// deselects it (logging a negative correction if it was ML-assigned); tapping
// the idle sparkle opens the category picker.
struct SparkleCategoryButton: View {
    @Bindable var vm: AddTransactionViewModel
    @Binding var showCategoryPicker: Bool

    @Environment(CategoryPredictor.self) private var predictor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                withAnimation(.dsMorph) {
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
                        .font(.system(size: vm.selectedCategory != nil ? 13 : 17, weight: .medium, relativeTo: .body))
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
        // Two triggers, one curve each — the previous four stacked implicit
        // animations (incl. an inner duplicate on the icon frame) competed on
        // the same subtree and fought over width/font/padding.
        .animation(.dsMorph, value: vm.selectedCategory?.id)
        .animation(.dsSpring, value: vm.sparkleActive)
    }
}
