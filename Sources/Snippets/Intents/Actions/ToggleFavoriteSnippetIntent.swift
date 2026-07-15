import AppIntents

struct ToggleFavoriteSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Snippet Favorite"
    static let description = IntentDescription("Adds or removes a snippet from favorites.")
    static let openAppWhenRun = false

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle favorite for \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext
        guard let model = try SnippetStore.snippet(uuid: snippet.id, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        model.isFavorite.toggle()
        model.updatedAt = .now
        try context.save()

        let name = model.title.isEmpty ? "Untitled" : model.title
        let dialog: IntentDialog = model.isFavorite
            ? "Added \(name) to favorites."
            : "Removed \(name) from favorites."
        return .result(value: model.isFavorite, dialog: dialog)
    }
}
