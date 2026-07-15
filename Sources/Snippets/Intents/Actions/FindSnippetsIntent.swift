import AppIntents
import SwiftData

struct FindSnippetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Snippets"
    static let description = IntentDescription("Finds snippets by text, collection, or favorites.")
    static let openAppWhenRun = false

    @Parameter(title: "Search Text")
    var searchText: String?

    @Parameter(title: "Collection")
    var collection: SnippetCollectionEntity?

    @Parameter(title: "Favorites Only", default: false)
    var favoritesOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Find snippets matching \(\.$searchText)") {
            \.$collection
            \.$favoritesOnly
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SnippetEntity]> {
        let context = SnippetsData.sharedModelContainer.mainContext
        let matched = try Self.execute(
            searchText: searchText, collectionID: collection?.id,
            favoritesOnly: favoritesOnly, in: context
        )
        return .result(value: matched.map(SnippetEntity.init))
    }

    /// Core logic, context-injected for tests.
    @MainActor
    static func execute(
        searchText: String?, collectionID: UUID?, favoritesOnly: Bool,
        in context: ModelContext
    ) throws -> [Snippet] {
        var descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }

        return SnippetQueryFilter.filter(
            snippets,
            query: searchText,
            collectionUUID: collectionID,
            favoritesOnly: favoritesOnly,
            projection: { snippet in
                SnippetQueryFilter.Candidate(
                    title: snippet.title,
                    description: snippet.snippetDescription,
                    language: snippet.language,
                    isFavorite: snippet.isFavorite,
                    collectionUUIDs: Set(snippet.collections.compactMap { $0.isDeleted ? nil : $0.uuid })
                )
            }
        )
    }
}
