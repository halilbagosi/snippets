import AppIntents
import SwiftData

struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Language") var language: String
    @Property(title: "Code") var code: String
    @Property(title: "Favorite") var isFavorite: Bool

    init(id: UUID, title: String, language: String, code: String, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.language = language
        self.code = code
        self.isFavorite = isFavorite
    }

    init(_ snippet: Snippet) {
        self.init(
            id: snippet.uuid ?? UUID(),
            title: snippet.title,
            language: snippet.language,
            // Truncate for display/transport; the full code is copied by CopySnippetIntent.
            code: String(snippet.code.prefix(4000)),
            isFavorite: snippet.isFavorite
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title.isEmpty ? "Untitled" : title)",
            subtitle: "\(language)"
        )
    }
}

struct SnippetEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        let wanted = Set(identifiers)
        return try fetchLive(context)
            .filter { $0.uuid.map(wanted.contains) ?? false }
            .map(SnippetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context, limit: 10).map(SnippetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context)
            .filter {
                SnippetQueryFilter.matches(
                    title: $0.title, description: $0.snippetDescription,
                    language: $0.language, query: string
                )
            }
            .map(SnippetEntity.init)
    }

    /// Fetches non-deleted snippets (newest first) and guarantees each has a
    /// stable `uuid`.
    @MainActor
    private func fetchLive(_ context: ModelContext, limit: Int? = nil) throws -> [Snippet] {
        var descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }
        return snippets
    }
}
