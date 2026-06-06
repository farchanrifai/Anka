import SwiftUI
import SwiftData

// MARK: - Keyboard height tracker

private struct KeyboardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var keyboardHeight: CGFloat {
        get { self[KeyboardHeightKey.self] }
        set { self[KeyboardHeightKey.self] = newValue }
    }
}

// MARK: - Amount + Note + Numpad section

private struct AmountInputSection<AboveNumpad: View, BelowNote: View>: View {
    @Binding var amount: Double
    @Binding var note: String
    var numpadHeight: CGFloat
    @ViewBuilder var aboveNumpad: AboveNumpad
    @ViewBuilder var belowNote: BelowNote

    @State private var amountString: String = "0"
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Equal spacers so amount+note are vertically centered in the blank area.
            Spacer()

            amountDisplay.padding(.horizontal, DSSpacing.xl)

            noteField
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.md)

            belowNote
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.sm)

            Spacer()

            aboveNumpad

            NumpadView(amountString: $amountString, onNoteTap: { noteFocused = true })
                .frame(height: numpadHeight)
                .opacity(noteFocused ? 0 : 1)
                .allowsHitTesting(!noteFocused)
                .animation(.none, value: noteFocused)
        }
        .contentShape(Rectangle())
        .onTapGesture { noteFocused = false }
        .onChange(of: amountString) { _, new in amount = Double(new) ?? 0 }
        .onAppear { if amount > 0 { amountString = String(Int(amount)) } }
        .onChange(of: amount) { _, new in
            let derived = Double(amountString) ?? 0
            if new != derived { amountString = new == 0 ? "0" : String(Int(new)) }
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Text("IDR")
                .font(.dsSubhead)
                .foregroundStyle(amount == 0 ? DSColor.textMuted : DSColor.textPrimary)
                .padding(.top, DSSpacing.sm)
            Text(amount == 0 ? "0" : amount.grouped)
                .font(.dsHero)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(amount == 0 ? DSColor.textMuted : DSColor.textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: amount)
        }
    }

    private var noteField: some View {
        TextField("Add note", text: $note)
            .focused($noteFocused)
            .multilineTextAlignment(.center)
            .font(.dsBody)
            .foregroundStyle(note.isEmpty ? DSColor.textMuted : DSColor.textPrimary)
            .submitLabel(.done)
            .onSubmit { noteFocused = false }
            .tint(DSColor.accent)
    }
}

// MARK: - Main view

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    var defaultType: TransactionType

    @State private var amount: Double
    @State private var selectedType: TransactionType
    @State private var selectedCategory: Category?
    @State private var selectedDate: Date
    @State private var note: String
    @State private var showCategoryPicker: Bool = false

    init(defaultType: TransactionType = .expense) {
        self.defaultType = defaultType
        _amount = State(initialValue: 0)
        _selectedType = State(initialValue: defaultType)
        _selectedCategory = State(initialValue: nil)
        _selectedDate = State(initialValue: Date())
        _note = State(initialValue: "")
    }

    // Exact keyboard height persisted to UserDefaults after the first keyboard appearance.
    // Guarantees zero layout shift on all subsequent launches.
    // Falls back to a screen-relative estimate only on the very first ever launch.
    // v2 key discards any stale value from earlier calibration experiments.
    private static let keyboardHeightKey = "anka.keyboardHeight.v2"
    @State private var numpadHeight: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: keyboardHeightKey)
        return stored > 0 ? stored : UIScreen.main.bounds.height * 0.345
    }()

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)

            AmountInputSection(amount: $amount, note: $note, numpadHeight: numpadHeight) {
                categoryAndSaveRow
                    .padding(.horizontal, DSSpacing.lg)
            } belowNote: {
                EmptyView()
            }
        }
        .background(DSColor.bgPrimary)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                numpadHeight = frame.height
                // Persist so future launches use the exact height from the start.
                UserDefaults.standard.set(frame.height, forKey: Self.keyboardHeightKey)
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(selectedCategory: selectedCategory) { category in
                selectedCategory = category
                selectedType = category.type
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.dsCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.bgCard, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Options placeholder (recurring lives in a later phase).
            Button {
            } label: {
                Image(systemName: "ellipsis")
                    .font(.dsCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.bgCard, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Date pill (functional)

    private var datePill: some View {
        VStack(spacing: 1) {
            Text(selectedDate.formatted(.dateTime.day(.twoDigits)))
                .font(.dsCaption)
                .fontWeight(.bold)
            Text(selectedDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.dsBadge)
        }
        .foregroundStyle(DSColor.textPrimary)
        .frame(width: 48, height: 48)
        .background(DSColor.bgCard, in: Circle())
        .overlay {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .scaleEffect(x: 2.0, y: 2.0)
                .blendMode(.destinationOver)
        }
        .clipped()
        .contentShape(Circle())
    }

    // MARK: - Category + Save row

    private var isSaveDisabled: Bool {
        amount == 0 || selectedCategory == nil
    }

    private var categoryAndSaveRow: some View {
        HStack(spacing: DSSpacing.md) {
            CategorySlotView(category: selectedCategory) {
                showCategoryPicker = true
            }

            Spacer()

            datePill

            Button {
                save()
            } label: {
                Text("Save")
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textOnAccent)
                    .padding(.horizontal, DSSpacing.xl)
                    .frame(height: 48)
                    .background(
                        isSaveDisabled ? DSColor.accent.opacity(0.35) : DSColor.accent,
                        in: Capsule()
                    )
            }
            .disabled(isSaveDisabled)
        }
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Logic

    private func save() {
        // Phase 2: UI only — persistence arrives in Phase 3.
        guard !isSaveDisabled else { return }
        dismiss()
    }
}

extension Double {
    /// Whole-number amount with thousands separators, e.g. 12345 → "12,345".
    var grouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? String(Int(self))
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(SampleData.container())
}
