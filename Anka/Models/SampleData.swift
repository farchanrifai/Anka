import SwiftData
import Foundation

struct SampleData {
    static func createDefaultCategories() -> [Category] {
        let expenseCategories = [
            ("Food & Dining", "🍔", "E74C3C", 0),
            ("Transport", "🚗", "3498DB", 1),
            ("Shopping", "🛍️", "E91E63", 2),
            ("Entertainment", "🎬", "9C27B0", 3),
            ("Utilities", "💡", "FF9800", 4),
            ("Health", "⚕️", "2ECC71", 5),
        ]

        let incomeCategories = [
            ("Salary", "💼", "27AE60", 0),
            ("Freelance", "💻", "16A085", 1),
            ("Investment", "📈", "2980B9", 2),
            ("Bonus", "🎁", "F39C12", 3),
            ("Other Income", "💰", "C0392B", 4),
            ("Refund", "↩️", "8E44AD", 5),
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
        let foodCategory = defaultCategories.first(where: { $0.name == "Food & Dining" })
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
