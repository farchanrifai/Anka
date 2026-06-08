import SwiftUI
import SwiftData

@main
struct AnkaApp: App {
    let modelContainer: ModelContainer

    /// ML predictor stays at app-root so the bundled + user models are loaded
    /// once for the app's lifetime — not on every AddTransaction sheet open.
    @State private var predictor = CategoryPredictor()

    /// App-lock manager — single source of truth for biometric/PIN state. Lives
    /// at app root so scene-phase changes can flip `isLocked` between transitions.
    @State private var lockManager = AppLockManager()

    /// Appearance manager — drives `.preferredColorScheme` + dark-variant
    /// overrides consumed by DSColor's dynamic background tokens.
    @State private var appearance = AppearanceManager()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let config = ModelConfiguration()
        let container = try! ModelContainer(for: Transaction.self, Category.self, configurations: config)

        Self.seedOrMigrateCategories(in: container.mainContext)

        self.modelContainer = container
    }

    /// First launch: seeds the 10/6 default taxonomy.
    /// Existing installs from Phase 5 (pre-ML) had a different taxonomy
    /// (Food & Dining / Transport / Utilities / Other Income / Refund) that
    /// the ML classifier can't match. This runs a one-time wipe of the
    /// known-old defaults and re-seeds the ML-aligned set. Transactions are
    /// preserved (unlinked from their old category, shown as Uncategorized)
    /// — `.cascade` would otherwise delete them along with the category.
    private static let categoryMigrationKey = "anka.categoryMigration.v2"
    private static func seedOrMigrateCategories(in context: ModelContext) {
        let defaults = UserDefaults.standard
        let categoryFetch = FetchDescriptor<Category>()
        let existing = (try? context.fetch(categoryFetch)) ?? []

        // Fresh install — just seed.
        if existing.isEmpty {
            for category in SampleData.createDefaultCategories() {
                context.insert(category)
            }
            try? context.save()
            defaults.set(true, forKey: categoryMigrationKey)
            return
        }

        // Already migrated — nothing to do.
        guard !defaults.bool(forKey: categoryMigrationKey) else { return }

        // Detect the old taxonomy by checking for names that only existed
        // in the pre-ML defaults. If none are present, we assume the user
        // has already curated their categories — skip and just flag done.
        let oldNames: Set<String> = [
            "Food & Dining", "Transport", "Utilities", "Other Income", "Refund"
        ]
        let oldCats = existing.filter { oldNames.contains($0.name) }

        if !oldCats.isEmpty {
            for category in oldCats {
                // Unlink transactions so cascade delete doesn't remove them.
                for tx in category.transactions {
                    tx.category = nil
                }
                context.delete(category)
            }
            try? context.save()

            // Insert any missing v2 defaults — don't duplicate names that
            // already exist (Salary / Freelance / Investment / Shopping /
            // Entertainment / Health / Bonus carry over by name).
            let nowExisting = (try? context.fetch(categoryFetch)) ?? []
            let presentNames = Set(nowExisting.map(\.name))
            for def in SampleData.createDefaultCategories() where !presentNames.contains(def.name) {
                context.insert(def)
            }
            try? context.save()
        }

        defaults.set(true, forKey: categoryMigrationKey)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppRouter()
                    .environment(predictor)
                    .environment(lockManager)
                    .environment(appearance)

                if lockManager.isLocked {
                    AppLockView()
                        .environment(lockManager)
                        .environment(appearance)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: lockManager.isLocked)
            .preferredColorScheme(appearance.mode.preferredColorScheme)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // Lock on background/inactive so the app contents aren't visible
            // in the iOS app switcher. Only re-lock if lock is enabled AND a
            // PIN is set — otherwise the user would be stranded with no way
            // back in.
            switch newPhase {
            case .background, .inactive:
                lockManager.lock()
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
