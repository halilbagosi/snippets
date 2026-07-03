import AppIntents
import SwiftData

struct SnippetCollectionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static let defaultQuery = SnippetCollectionEntityQuery()

    let id: UUID
    @Property(title: "Name") var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ collection: SnippetCollection) {
        self.init(id: collection.uuid ?? UUID(), name: collection.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SnippetCollectionEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetCollectionEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        let all = try fetchLive(context)
        let wanted = Set(identifiers)
        return all
            .filter { $0.uuid.map(wanted.contains) ?? false }
            .map(SnippetCollectionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetCollectionEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context).map(SnippetCollectionEntity.init)
    }

    /// Fetches non-deleted collections and guarantees each has a stable `uuid`.
    @MainActor
    private func fetchLive(_ context: ModelContext) throws -> [SnippetCollection] {
        var descriptor = FetchDescriptor<SnippetCollection>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let collections = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: [], collections: collections) > 0 {
            try? context.save()
        }
        return collections
    }
}
