import AppIntents
import SwiftData

struct FindSnippetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Snippets"
    static let description = IntentDescription("Finds snippets by text, collection, or favorites.")
    static let openAppWhenRun = false

    /// Bounds what Shortcuts receives, however large the library is.
    static let resultLimit = 200

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
        let descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }

        // Filter the whole library, then cap. Capping the fetch instead made
        // anything older than the 200 most recently edited snippets
        // unfindable, with no error to say so.
        let matched = SnippetQueryFilter.filter(
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
        return Array(matched.prefix(Self.resultLimit))
    }
}
