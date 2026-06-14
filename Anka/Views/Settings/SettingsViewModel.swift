import SwiftUI
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {
    var categories: [Category] = []
    var showAddCategory: Bool = false
    var editingCategory: Category?

    var newCategoryName: String = ""
    var newCategoryEmoji: String = "💳"
    var newCategoryColor: String = "F26666"
    var newCategoryType: TransactionType = .expense

    /// Non-nil when a category save/delete/reorder fails to persist — surfaced
    /// as an alert (AUDIT.md A5, replacing the old silent `try?`).
    var categoryErrorMessage: String?

    /// Preset swatches offered in the category editor (U10) — every custom
    /// category used to be coral `F26666`, which made the Stats donut render
    /// multiple identical slices. Hex strings without `#`.
    static let categoryColorOptions: [String] = [
        "F26666", "FF8A65", "FFB74D", "FFD54F", "AED581", "4DB6AC",
        "4FC3F7", "7986CB", "BA68C8", "F06292", "A1887F", "90A4AE",
    ]

    /// Default category names the bundled ML classifier + KeywordMatcher emit.
    /// Renaming one silently severs auto-categorization (labels are name-coupled
    /// — see CONTEXT "Category-name coupling"). Used to warn in the editor.
    static let mlLockedNames: Set<String> = [
        "Home", "Groceries", "Eating Out", "Food Delivery", "Coffee", "Car",
        "Taxi", "Health", "Shopping", "Entertainment",
        "Salary", "Freelance", "Investment",
    ]

    func update(categories: [Category]) {
        self.categories = categories
    }

    func startAddCategory() {
        editingCategory = nil
        newCategoryName = ""
        newCategoryEmoji = "💳"
        newCategoryColor = "F26666"
        newCategoryType = .expense
        showAddCategory = true
    }

    func startEditCategory(_ category: Category) {
        editingCategory = category
        newCategoryName = category.name
        newCategoryEmoji = category.emoji
        newCategoryColor = category.colorHex
        newCategoryType = category.type
        showAddCategory = true
    }

    func cancelEdit() {
        showAddCategory = false
        editingCategory = nil
    }

    var trimmedName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the emoji field holds exactly one emoji grapheme — accepts
    /// single emoji, ZWJ sequences (👨‍👩‍👧), and flags (🇮🇩); rejects letters,
    /// digits, and multi-character input (U11).
    var isEmojiValid: Bool {
        let e = newCategoryEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.count == 1 else { return false }
        let scalars = Array(e.unicodeScalars)
        let hasEmojiPresentation = scalars.contains { $0.properties.isEmojiPresentation }
        let isEmojiSequence = scalars.count > 1 && scalars.contains { $0.properties.isEmoji }
        return hasEmojiPresentation || isEmojiSequence
    }

    /// True when `newCategoryName` collides (case-insensitively) with another
    /// existing category — name uniqueness matters because ML matching is
    /// name-based. Excludes the category currently being edited.
    var isDuplicateName: Bool {
        let n = trimmedName.lowercased()
        guard !n.isEmpty else { return false }
        return categories.contains { $0.name.lowercased() == n && $0.id != editingCategory?.id }
    }

    /// True when editing one of the ML-coupled default categories and the name
    /// is being changed — renaming it breaks auto-categorization (U-rename warn).
    var willBreakMLMatching: Bool {
        guard let original = editingCategory?.name else { return false }
        return Self.mlLockedNames.contains(original) && trimmedName != original
    }

    var isFormValid: Bool {
        !trimmedName.isEmpty && isEmojiValid && !isDuplicateName
    }
}
