import SwiftUI
import SwiftData

@main
struct AnkaApp: App {
    /// Outcome of building the on-disk store. Held in `@State` (not a plain
    /// `let`) so the error screen's "Try Again" can rebuild the container
    /// without relaunching the app. Previously this used `try!`, which
    /// hard-crashed on any store-open failure (corruption, migration, disk
    /// full) with no recovery path.
    @State private var containerResult: Result<ModelContainer, Error>

    /// ML predictor stays at app-root so the bundled + user models are loaded
    /// once for the app's lifetime — not on every AddTransaction sheet open.
    @State private var predictor = CategoryPredictor()

    /// App-lock manager — single source of truth for biometric/PIN state. Lives
    /// at app root so scene-phase changes can flip `isLocked` between transitions.
    @State private var lockManager = AppLockManager()

    /// Appearance manager — drives `.preferredColorScheme` + dark-variant
    /// overrides consumed by DSColor's dynamic background tokens.
    @State private var appearance = AppearanceManager()

    /// Routes deep links from widgets (W3) into navigation state.
    @State private var deepLinkRouter = DeepLinkRouter()

    @Environment(\.scenePhase) private var scenePhase

    /// First-run gate: onboarding overlays the app until completed. The
    /// subscription/demo buttons on its last page are placeholders (Phase 9).
    @AppStorage("anka.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        _containerResult = State(initialValue: Result { try Self.makeContainer() })
    }

    /// Builds the on-disk `ModelContainer` and seeds/migrates the default
    /// categories. Throws (rather than crashing) if the store can't be opened
    /// so the caller can surface a recovery UI.
    private static func makeContainer() throws -> ModelContainer {
        let container = try AnkaModelContainer.makeContainer()
        seedOrMigrateCategories(in: container.mainContext)
        return container
    }

    /// "Try Again" — re-attempt opening the existing store.
    private func retryLoadingContainer() {
        containerResult = Result { try Self.makeContainer() }
    }

    /// "Reset App Data" — delete the store file (and its -wal/-shm sidecars)
    /// then build a fresh, empty container.
    private func resetStore() {
        let fm = FileManager.default
        let base = AnkaModelContainer.makeConfiguration().url.path
        for path in [base, base + "-wal", base + "-shm"] {
            try? fm.removeItem(atPath: path)
        }
        containerResult = Result { try Self.makeContainer() }
    }

    /// First launch: seeds the 10/6 default taxonomy.
    /// Existing installs from Phase 5 (pre-ML) had a different taxonomy
    /// (Food & Dining / Transport / Utilities / Other Income / Refund) that
    /// the ML classifier can't match. This runs a one-time wipe of the
    /// known-old defaults and re-seeds the ML-aligned set. Transactions are
    /// preserved (unlinked from their old category, shown as Uncategorized)
    /// — `.cascade` would otherwise delete them along with the category.
    static let categoryMigrationKey = "anka.categoryMigration.v2"
    static func seedOrMigrateCategories(in context: ModelContext, defaults: UserDefaults = .standard) {
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
            switch containerResult {
            case .success(let container):
                rootView
                    .modelContainer(container)
            case .failure:
                DataLoadErrorView(
                    onRetry: retryLoadingContainer,
                    onReset: resetStore
                )
                .preferredColorScheme(appearance.mode.preferredColorScheme)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Cover the UI on background/inactive so contents aren't visible in
            // the iOS app switcher; on return, `enterForeground` decides whether
            // the grace period allows a silent unlock. Both bail unless lock is
            // enabled AND a PIN is set, so the user is never stranded.
            switch newPhase {
            case .background, .inactive:
                lockManager.enterBackground()
            case .active:
                lockManager.enterForeground()
            @unknown default:
                break
            }
        }
    }

    /// The normal app UI, shown once the store opens successfully.
    private var rootView: some View {
        ZStack {
            AppRouter()
                .environment(predictor)
                .environment(lockManager)
                .environment(appearance)
                .environment(deepLinkRouter)

            if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .environment(appearance)
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }

            if lockManager.isLocked {
                AppLockView()
                    .environment(lockManager)
                    .environment(appearance)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lockManager.isLocked)
        .animation(.easeInOut(duration: 0.35), value: hasCompletedOnboarding)
        .preferredColorScheme(appearance.mode.preferredColorScheme)
        // W3: Handle widget deep links. The `anka://` URL scheme must be
        // registered in the app target's Info.plist (URL Types → anka).
        .onOpenURL { url in
            deepLinkRouter.handle(url)
        }
    }
}

// MARK: - Data Load Error Screen

/// Shown when the on-disk `ModelContainer` fails to open. Offers a non-fatal
/// recovery path: retry, or wipe the store and start fresh. Uses DSColor
/// tokens only (no `@Environment` appearance available this early at root).
private struct DataLoadErrorView: View {
    let onRetry: () -> Void
    let onReset: () -> Void

    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            DSColor.bgPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48, relativeTo: .largeTitle))
                    .foregroundStyle(DSColor.accent)

                VStack(spacing: 8) {
                    Text("Something went wrong loading your data.")
                        .font(.dsHeadline)
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("You can try again, or reset the app's data to start fresh.")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.dsSubhead)
                            .foregroundStyle(DSColor.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DSColor.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("Reset App Data")
                            .font(.dsSubhead)
                            .foregroundStyle(DSColor.negative)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)
        }
        .alert("Reset App Data?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive, action: onReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all transactions and categories on this device. This cannot be undone.")
        }
    }
}
