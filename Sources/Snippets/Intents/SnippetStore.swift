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

    /// Record that a snippet's code was copied.
    ///
    /// The single definition of copy bookkeeping, shared by the App Intent
    /// (which looks the snippet up by uuid first) and the menu bar panel
    /// (which already holds the model). `updatedAt` is deliberately untouched:
    /// the gallery orders by it, and copying should not reshuffle the grid.
    ///
    /// `copyCount` feeds the panel's "Frequent" scope, so every copy path in
    /// the app must come through here or that scope drifts away from real use.
    static func recordCopy(_ snippet: Snippet, in context: ModelContext) {
        snippet.copyCount += 1
        try? context.save()
    }

    static func collection(uuid: UUID, in context: ModelContext) throws -> SnippetCollection? {
        let all = try context.fetch(
            FetchDescriptor<SnippetCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return all.first { $0.uuid == uuid }
    }
}
