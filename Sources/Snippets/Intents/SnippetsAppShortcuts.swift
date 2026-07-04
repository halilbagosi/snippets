import AppIntents

/// Siri / Spotlight phrases for the app's primary intents. Phrases must include
/// `\(.applicationName)`. Discovery of these requires the App Intents metadata
/// that Xcode generates at build time (not produced by a plain `swift build`).
struct SnippetsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Voice/Spotlight "create" opens the editor via NewSnippetIntent — Siri
        // can't supply free-form code, so CreateSnippetIntent (required title +
        // code) can't be fulfilled by phrase. CreateSnippetIntent stays available
        // as a Shortcuts building block for automations that provide those values.
        AppShortcut(
            intent: NewSnippetIntent(),
            phrases: [
                "Create a snippet in \(.applicationName)",
                "Add a snippet to \(.applicationName)"
            ],
            shortTitle: "Create Snippet",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: FindSnippetsIntent(),
            phrases: [
                "Find snippets in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Find Snippets",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CopySnippetIntent(),
            phrases: [
                "Copy a snippet from \(.applicationName)"
            ],
            shortTitle: "Copy Snippet",
            systemImageName: "doc.on.doc"
        )
    }
}
