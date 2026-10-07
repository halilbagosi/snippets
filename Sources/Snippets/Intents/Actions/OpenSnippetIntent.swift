import AppIntents

struct OpenSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Snippet"
    static let description = IntentDescription("Opens a snippet in Snippets.")
    static let openAppWhenRun = true

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentNavigator.shared.pendingOpenSnippetUUID = snippet.id
        return .result()
    }
}
