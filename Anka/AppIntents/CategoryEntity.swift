import AppIntents
import SwiftData

/// Siri/Shortcuts-facing wrapper around `Category`, used as the `category`
/// parameter for `AddTransactionIntent`.
struct CategoryEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let type: TransactionType

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    static let defaultQuery = CategoryEntityQuery()

    init(from category: Category) {
        self.id = category.id
        self.name = category.name
        self.emoji = category.emoji
        self.type = category.type
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let context = try AnkaModelContainer.makeContext()
        let all = try context.allCategories()
        return all
            .filter { identifiers.contains($0.id) }
            .map(CategoryEntity.init(from:))
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        let context = try AnkaModelContainer.makeContext()
        return try context.allCategories().map(CategoryEntity.init(from:))
    }
}
