import AppIntents
import SwiftData

enum SnippetIntentError: Error, CustomLocalizedStringResourceConvertible {
    case snippetNotFound
    case collectionNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .snippetNotFound: "That snippet no longer exists."
        case .collectionNotFound: "That collection no longer exists."
        }
    }
}

/// Shared, `uuid`-keyed lookups over the live (non-deleted) store for intents.
@MainActor
enum SnippetStore {
    static func snippet(uuid: UUID, in context: ModelContext) throws -> Snippet? {
        let all = try context.fetch(
            FetchDescriptor<Snippet>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return all.first { $0.uuid == uuid }
    }

    static func collection(uuid: UUID, in context: ModelContext) throws -> SnippetCollection? {
        let all = try context.fetch(
            FetchDescriptor<SnippetCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return all.first { $0.uuid == uuid }
    }
}
