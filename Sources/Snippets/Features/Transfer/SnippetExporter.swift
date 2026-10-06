import Foundation
import SwiftData

/// Turns library models into a `SnippetArchive`. Trash never leaves, and
/// preview trust is not part of the models, so it cannot leave either.
@MainActor
enum SnippetExporter {
    /// - Parameters:
    ///   - snippets: exported on their own; their collections and every
    ///     ancestor of those come along so the nesting rebuilds on import.
    ///   - collections: exported whole — the subtree (empty children too) and
    ///     every snippet in it.
    ///   - mediaData: reads an attachment's bytes; nil drops the attachment.
    static func archive(
        snippets: [Snippet],
        collections: [SnippetCollection],
        appVersion: String,
        now: Date = .now,
        mediaData: (MediaItem) -> Data?
    ) -> SnippetArchive {
        var includedCollections: [SnippetCollection] = []
        var seenCollections = Set<PersistentIdentifier>()
        func addCollection(_ collection: SnippetCollection) {
            guard !collection.isDeleted, seenCollections.insert(collection.persistentModelID).inserted else { return }
            includedCollections.append(collection)
        }

        var includedSnippets: [Snippet] = []
        var seenSnippets = Set<PersistentIdentifier>()
        func addSnippet(_ snippet: Snippet) {
            guard !snippet.isDeleted, seenSnippets.insert(snippet.persistentModelID).inserted else { return }
            includedSnippets.append(snippet)
        }

        func addSubtree(_ collection: SnippetCollection) {
            guard !collection.isDeleted else { return }
            addCollection(collection)
            collection.snippets.forEach(addSnippet)
            collection.children.forEach(addSubtree)
        }

        collections.forEach(addSubtree)
        snippets.forEach(addSnippet)
        for snippet in includedSnippets { snippet.collections.forEach(addCollection) }
        // Grows while iterating: each added parent gets its own parent checked.
        var index = 0
        while index < includedCollections.count {
            if let parent = includedCollections[index].parent { addCollection(parent) }
            index += 1
        }

        // Rows predating the uuid backfill get one now, so a re-export is stable
        // and an import can recognise them. The caller saves the context.
        for collection in includedCollections where collection.uuid == nil { collection.uuid = UUID() }
        for snippet in includedSnippets where snippet.uuid == nil { snippet.uuid = UUID() }

        let collectionRecords = includedCollections
            .sorted { ($0.createdAt, $0.uuid!.uuidString) < ($1.createdAt, $1.uuid!.uuidString) }
            .map { collection in
                SnippetArchive.CollectionRecord(
                    id: collection.uuid!,
                    name: collection.name,
                    colorHex: collection.colorHex,
                    colorHexDark: collection.colorHexDark,
                    iconName: collection.iconName,
                    parentID: collection.parent?.uuid,
                    isFavorite: collection.isFavorite,
                    createdAt: collection.createdAt,
                    updatedAt: collection.updatedAt
                )
            }

        let snippetRecords = includedSnippets
            .sorted { ($0.createdAt, $0.uuid!.uuidString) < ($1.createdAt, $1.uuid!.uuidString) }
            .map { snippet in
                SnippetArchive.SnippetRecord(
                    id: snippet.uuid!,
                    title: snippet.title,
                    description: snippet.snippetDescription,
                    language: snippet.language,
                    code: snippet.code,
                    createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt,
                    isFavorite: snippet.isFavorite,
                    copyCount: snippet.copyCount,
                    collectionIDs: snippet.collections.compactMap(\.uuid).sorted { $0.uuidString < $1.uuidString },
                    dependencyIDs: snippet.dependencies.compactMap(\.uuid),
                    paramConfigs: snippet.paramConfigs,
                    activeParamConfigID: snippet.activeParamConfigID,
                    media: snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }.compactMap { item in
                        guard let data = mediaData(item) else { return nil }
                        return SnippetArchive.MediaRecord(
                            kind: item.fileTypeRaw,
                            fileExtension: (item.fileName as NSString).pathExtension.lowercased(),
                            addedAt: item.addedAt,
                            data: data
                        )
                    }
                )
            }

        // `sanitized` is the one place that drops references leaving the file
        // (dependencies outside the export, trashed collections, unknown ids).
        return SnippetArchive(exportedAt: now, appVersion: appVersion,
                              collections: collectionRecords, snippets: snippetRecords).sanitized()
    }
}
