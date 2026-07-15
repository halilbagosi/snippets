import Foundation
import SwiftData


@Model
final class SnippetCollection {
    static let defaultColorHex = "#0A84FF"
    static let defaultIconName = "curlybraces"

    var name: String
    var colorHex: String = SnippetCollection.defaultColorHex
    var colorHexDark: String?
    var iconName: String = SnippetCollection.defaultIconName
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isFavorite: Bool = false
    var uuid: UUID?

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
        name: String,
        colorHex: String = SnippetCollection.defaultColorHex,
        colorHexDark: String? = nil,
        iconName: String = SnippetCollection.defaultIconName,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        isFavorite: Bool = false,
        snippets: [Snippet] = [],
        parent: SnippetCollection? = nil,
        children: [SnippetCollection] = []
    ) {
        self.uuid = uuid
        self.name = name
        self.colorHex = colorHex
        self.colorHexDark = colorHexDark
        self.iconName = iconName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isFavorite = isFavorite
        self.snippets = snippets
        self.parent = parent
        self.children = children
    }

    func resolvedColorHex(isDark: Bool) -> String {
        if isDark, let darkHex = colorHexDark {
            return darkHex
        }
        return colorHex
    }
}
