import AppIntents
import SwiftData

struct CreateSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Snippet"
    static let description = IntentDescription("Creates a new snippet in Snippets.")
    static let openAppWhenRun = false

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Code")
    var code: String

    @Parameter(title: "Language", default: "Unknown")
    var language: String

    @Parameter(title: "Collection")
    var collection: SnippetCollectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Create snippet \(\.$title)") {
            \.$code
            \.$language
            \.$collection
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SnippetEntity> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext

        let snippet = Snippet(
            title: title,
            language: language,
            code: code
        )
        context.insert(snippet)

        if let collection {
            guard let target = try SnippetStore.collection(uuid: collection.id, in: context) else {
                throw SnippetIntentError.collectionNotFound
            }
            snippet.collections.append(target)
            target.updatedAt = .now
        }
        try? context.save()

        let name = title.isEmpty ? "Untitled" : title
        return .result(value: SnippetEntity(snippet), dialog: "Created \(name).")
    }
}
