import SwiftData
import Foundation

struct SampleData {
    /// IMPORTANT: These names are tightly coupled to the ML classifier labels
    /// (Services/CategoryPredictor.swift). The bundled StarterCategoryClassifier
    /// and KeywordMatcher emit exactly these strings — renaming any of them
    /// will silently break ML auto-categorization for that category.
    static func createDefaultCategories() -> [Category] {
        let expenseCategories = [
            ("Home",          "🏠", "7E57C2", 0),
            ("Groceries",     "🛒", "FF6B6B", 1),
            ("Eating Out",    "🍽️", "FF6B6B", 2),
            ("Food Delivery", "🥡", "FF6B6B", 3),
            ("Coffee",        "☕", "FF8A65", 4),
            ("Car",           "🚗", "42A5F5", 5),
            ("Taxi",          "🚕", "42A5F5", 6),
            ("Health",        "💊", "66BB6A", 7),
            ("Shopping",      "🛍️", "EC407A", 8),
            ("Entertainment", "🎬", "FFA726", 9),
        ]

        let incomeCategories = [
            ("Salary",       "💼", "66BB6A", 0),
            ("Freelance",    "💻", "42A5F5", 1),
            ("Investment",   "📈", "FFCA28", 2),
            ("Bonus",        "🎁", "F39C12", 3),
            ("Other Income", "💰", "C0392B", 4),
            ("Refund",       "↩️", "8E44AD", 5),
        ]

        var categories: [Category] = []

        for (name, emoji, hex, sortOrder) in expenseCategories {
            categories.append(
                Category(
                    name: name,
                    emoji: emoji,
                    colorHex: hex,
                    type: .expense,
                    sortOrder: sortOrder
                )
            )
        }

        for (name, emoji, hex, sortOrder) in incomeCategories {
            categories.append(
                Category(
                    name: name,
                    emoji: emoji,
                    colorHex: hex,
                    type: .income,
                    sortOrder: sortOrder
                )
            )
        }

        return categories
    }

    static func container() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Transaction.self, Category.self, configurations: config)

        let defaultCategories = createDefaultCategories()
        for category in defaultCategories {
            container.mainContext.insert(category)
        }

        // Add 3 sample transactions for testing
        let foodCategory = defaultCategories.first(where: { $0.name == "Eating Out" })
        let salaryCategory = defaultCategories.first(where: { $0.name == "Salary" })

        let today = Date()
        let transactions = [
            Transaction(amount: 15.50, type: .expense, date: today, note: "Lunch", category: foodCategory),
            Transaction(amount: 45.00, type: .expense, date: today.addingTimeInterval(-86400), note: "Dinner", category: foodCategory),
            Transaction(amount: 5000.00, type: .income, date: today, note: "Monthly salary", category: salaryCategory),
        ]

        for transaction in transactions {
            container.mainContext.insert(transaction)
        }

        return container
    }
}
