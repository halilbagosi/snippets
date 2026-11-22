import Foundation
import SwiftData


@Model
final class Snippet {
    var title: String
    var snippetDescription: String
    var language: String
    var code: String
    var createdAt: Date
    var updatedAt: Date
    var copyCount: Int = 0
    var isFavorite: Bool = false
    var deletedAt: Date?
    var uuid: UUID?

    /// Saved preview parameter configurations. Both properties carry defaults
    /// so existing rows migrate without intervention.
    var paramConfigs: [PreviewParamConfig] = []
    var activeParamConfigID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.snippet)
    var mediaItems: [MediaItem]

    @Relationship(inverse: \SnippetCollection.snippets)
    var collections: [SnippetCollection]

    /// Snippets this snippet needs to build a combined live preview.
    /// The order is the one the app last wrote, but SwiftData does not
    /// guarantee to-many order across saves.
    @Relationship(inverse: \Snippet.dependents)
    var dependencies: [Snippet] = []

    var dependents: [Snippet] = []

    var isDeleted: Bool {
        deletedAt != nil
    }

    var daysUntilPermanentDeletion: Int {
        guard let deletedAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: Date.now).day ?? 0
        return max(30 - elapsed, 0)
    }

    init(
        uuid: UUID? = UUID(),
        title: String = "",
        snippetDescription: String = "",
        language: String = "Unknown",
        code: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        copyCount: Int = 0,
        isFavorite: Bool = false,
        deletedAt: Date? = nil,
        mediaItems: [MediaItem] = [],
        collections: [SnippetCollection] = []
    ) {
        self.uuid = uuid
        self.title = title
        self.snippetDescription = snippetDescription
        self.language = language
        self.code = code
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.copyCount = copyCount
        self.isFavorite = isFavorite
        self.deletedAt = deletedAt
        self.mediaItems = mediaItems
        self.collections = collections
    }
}

extension Snippet {
    /// The uuids whose preview approvals stop being valid when this snippet's
    /// code is replaced: its own, then every snippet whose combined preview
    /// runs it — dependents, their dependents, and so on. Trashed snippets
    /// are included and walked through: a restored snippet must not come
    /// back holding approval for code that changed while it was in Trash.
    /// Each uuid appears once; this snippet's own comes first.
    var uuidsRunningThisCode: [UUID] {
        var visited: Set<PersistentIdentifier> = [persistentModelID]
        var ordered: [UUID] = uuid.map { [$0] } ?? []
        var queue = dependents
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard visited.insert(next.persistentModelID).inserted else { continue }
            if let id = next.uuid { ordered.append(id) }
            queue.append(contentsOf: next.dependents)
        }
        return ordered
    }
}
