import AppIntents

/// Siri / Spotlight phrases for the app's primary intents. Phrases must include
/// `\(.applicationName)`. Discovery of these requires the App Intents metadata
/// that Xcode generates at build time (not produced by a plain `swift build`).
struct SnippetsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateSnippetIntent(),
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
