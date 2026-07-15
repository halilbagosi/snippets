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

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.snippet)
    var mediaItems: [MediaItem]

    @Relationship(inverse: \SnippetCollection.snippets)
    var collections: [SnippetCollection]

    /// Snippets this snippet needs to build a combined live preview.
    /// Array order is the user's arranged order and is preserved.
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
