import Foundation
import SwiftData


@Model
final class Collection {
    var name: String
    var createdAt: Date
    var updatedAt: Date

    var snippets: [Snippet]

    init(
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        snippets: [Snippet] = []
    ) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.snippets = snippets
    }
}
