import SwiftUI
import SwiftData

@main
struct AnkaApp: App {
    let modelContainer: ModelContainer

    init() {
        let config = ModelConfiguration()
        let container = try! ModelContainer(for: Transaction.self, Category.self, configurations: config)

        // Insert default categories if the container is empty
        let categoryFetch = FetchDescriptor<Category>()
        if (try? container.mainContext.fetchCount(categoryFetch)) == 0 {
            let defaultCategories = SampleData.createDefaultCategories()
            for category in defaultCategories {
                container.mainContext.insert(category)
            }
        }

        self.modelContainer = container
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
        }
        .modelContainer(modelContainer)
    }
}
