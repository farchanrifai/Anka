import AppIntents
import SwiftData

/// Shared SwiftData access for App Intents (Siri/Shortcuts). Intents run
/// in-process in the main app target, so opening a container with the same
/// schema + default `ModelConfiguration()` as `AnkaApp.makeContainer()`
/// points at the same on-disk store.
enum AnkaModelContainer {
    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration()
    }

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Transaction.self, Category.self, configurations: makeConfiguration())
    }

    @MainActor
    static func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    /// Cached so repeated intent invocations within the same process don't
    /// reload the CoreML category-prediction model every time.
    @MainActor
    static let predictor = CategoryPredictor()
}

extension ModelContext {
    /// All categories, sorted for display (Siri/Shortcuts category lists).
    func allCategories() throws -> [Category] {
        try fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    /// Looks up a category by id (Siri/Shortcuts entity resolution).
    func category(id: UUID) throws -> Category? {
        try fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first
    }
}

/// Posts the same change notification + widget refresh that the in-app save
/// paths trigger, so the dashboard and widgets stay in sync after a
/// Siri/Shortcuts-driven save.
@MainActor
func postSaveSideEffects(context: ModelContext) {
    NotificationCenter.default.post(name: .ankaDataDidChange, object: nil)
    let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    WidgetDataWriter.shared.updateWidgetData(transactions: transactions)
}
