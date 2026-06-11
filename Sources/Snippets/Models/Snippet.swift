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

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.snippet)
    var mediaItems: [MediaItem]

    @Relationship(inverse: \SnippetCollection.snippets)
    var collections: [SnippetCollection]

    var isDeleted: Bool {
        deletedAt != nil
    }

    var daysUntilPermanentDeletion: Int {
        guard let deletedAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: Date.now).day ?? 0
        return max(30 - elapsed, 0)
    }

    init(
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
