import AppIntents
import SwiftData

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
        let model = try Self.execute(snippetID: snippet.id, in: context)
        Clipboard.copy(model.code)

        let name = model.title.isEmpty ? "Untitled" : model.title
        return .result(value: model.code, dialog: "Copied \(name).")
    }

    /// Lookup + bookkeeping, context-injected for tests. The clipboard write
    /// stays in `perform()`.
    @MainActor
    static func execute(snippetID: UUID, in context: ModelContext) throws -> Snippet {
        guard let model = try SnippetStore.snippet(uuid: snippetID, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        SnippetStore.recordCopy(model, in: context)
        return model
    }
}
