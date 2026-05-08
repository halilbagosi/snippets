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

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.snippet)
    var mediaItems: [MediaItem]

    @Relationship(inverse: \SnippetCollection.snippets)
    var collections: [SnippetCollection]

    init(
        title: String = "",
        snippetDescription: String = "",
        language: String = "Unknown",
        code: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        mediaItems: [MediaItem] = [],
        collections: [SnippetCollection] = []
    ) {
        self.title = title
        self.snippetDescription = snippetDescription
        self.language = language
        self.code = code
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mediaItems = mediaItems
        self.collections = collections
    }
}
