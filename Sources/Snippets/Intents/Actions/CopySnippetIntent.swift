import AppIntents

struct CopySnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet Code"
    static let description = IntentDescription("Copies a snippet's code to the clipboard.")
    static let openAppWhenRun = false

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copy code from \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext
        guard let model = try SnippetStore.snippet(uuid: snippet.id, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        Clipboard.copy(model.code)
        // Mirror in-app copy: bump copyCount (feeds "Frequently Used"); leave
        // updatedAt untouched so the gallery order doesn't shift.
        model.copyCount += 1
        try? context.save()

        let name = model.title.isEmpty ? "Untitled" : model.title
        return .result(value: model.code, dialog: "Copied \(name).")
    }
}
