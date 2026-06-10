import SwiftUI
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {
    var categories: [Category] = []
    var defaultCurrency: String = "IDR"
    var showAddCategory: Bool = false
    var editingCategory: Category?

    var newCategoryName: String = ""
    var newCategoryEmoji: String = "💳"
    var newCategoryColor: String = "F26666"
    var newCategoryType: TransactionType = .expense

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

    var isFormValid: Bool {
        !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
            && !newCategoryEmoji.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
