import AppIntents

/// Opens Snippets to a blank new-snippet editor.
///
/// This is the voice/Spotlight entry point for creating a snippet. A spoken or
/// Spotlight invocation can't supply free-form code (and App Shortcut phrases
/// can't carry free-form `String` parameters), so the "Create a snippet" App
/// Shortcut opens the composer instead of creating a snippet headlessly. The
/// headless `CreateSnippetIntent` (with its `title`/`code` parameters) remains
/// available for Shortcuts automations where the user supplies those values.
struct NewSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "New Snippet"
    static let description = IntentDescription("Opens Snippets to create a new snippet.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentNavigator.shared.pendingNewSnippet = true
        return .result()
    }
}
