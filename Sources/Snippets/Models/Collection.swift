import Foundation
import SwiftData


@Model
final class SnippetCollection {
    static let defaultColorHex = "#0A84FF"
    static let defaultIconName = "curlybraces"

    var name: String
    var colorHex: String = SnippetCollection.defaultColorHex
    var iconName: String = SnippetCollection.defaultIconName
    var createdAt: Date
    var updatedAt: Date

    var snippets: [Snippet]

    var parent: SnippetCollection?

    @Relationship(deleteRule: .cascade, inverse: \SnippetCollection.parent)
    var children: [SnippetCollection]

    var allDescendantIDs: Set<PersistentIdentifier> {
        var ids = Set([self.persistentModelID])
        for child in children {
            ids.formUnion(child.allDescendantIDs)
        }
        return ids
    }

    init(
        name: String,
        colorHex: String = SnippetCollection.defaultColorHex,
        iconName: String = SnippetCollection.defaultIconName,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        snippets: [Snippet] = [],
        parent: SnippetCollection? = nil,
        children: [SnippetCollection] = []
    ) {
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.snippets = snippets
        self.parent = parent
        self.children = children
    }
}
