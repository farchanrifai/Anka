import AppIntents

/// Exposes Anka's two add-transaction intents to Siri and the Shortcuts app.
///
/// `QuickAddTransactionIntent` is the primary Siri-facing one. Only
/// `AppEntity`/`AppEnum` parameters can be embedded directly in a phrase, so
/// its `text: String` parameter can't appear inline — Siri instead prompts
/// for it (via `IntentDialog`/`needsValueError` in `perform()`) after
/// matching one of these phrases, then the user dictates the free-form
/// amount/note (e.g. "50k for coffee"), which is parsed exactly like the V3
/// inline composer.
struct AnkaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddTransactionIntent(),
            phrases: [
                "Quick add to \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
            ],
            shortTitle: "Quick Add",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add transaction in \(.applicationName)",
                "New \(.applicationName) transaction",
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle"
        )
    }
}
