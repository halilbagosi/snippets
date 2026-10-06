import Foundation
import SwiftData

/// A snippet in the file whose id is already in the library (Trash included).
struct ImportConflict: Equatable {
    let id: UUID
    /// The local snippet's title — the one the user knows.
    let title: String
    let isInTrash: Bool
}

enum ConflictChoice: Equatable { case skip, replace, stop }

struct ConflictResolution: Equatable {
    var choice: ConflictChoice
    var applyToAll: Bool
}

struct ImportSummary: Equatable {
    var added = 0
    var replaced = 0
    var skipped = 0
    var stopped = false

    /// "Imported 12 snippets · 3 replaced · 30 skipped"
    var message: String {
        let noun = added == 1 ? "snippet" : "snippets"
        var parts = [stopped ? "Import stopped after \(added) \(noun)" : "Imported \(added) \(noun)"]
        if replaced > 0 { parts.append("\(replaced) replaced") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }
}

/// Writes a validated `SnippetArchive` into the library. File and trust side
/// effects go through closures so the rules are testable without the media
/// directory or `PreviewTrust`.
@MainActor
struct SnippetImporter {
    /// Stores attachment bytes with the given (validated) extension; returns the file name.
    var writeMedia: @MainActor (Data, String) throws -> String
    /// Deletes a replaced attachment's file. Called only after the save succeeded.
    var removeMedia: @MainActor (String) -> Void
    /// Drops preview permissions for a replaced snippet.
    var forgetTrust: @MainActor (UUID) -> Void

    func apply(
        _ archive: SnippetArchive,
        to context: ModelContext,
        resolve: @MainActor (ImportConflict) async -> ConflictResolution
    ) async throws -> ImportSummary {
        var snippetsByID: [UUID: Snippet] = [:]
        for snippet in try context.fetch(FetchDescriptor<Snippet>()) {
            if let id = snippet.uuid { snippetsByID[id] = snippet }
        }
        var collectionsByID: [UUID: SnippetCollection] = [:]
        for collection in try context.fetch(FetchDescriptor<SnippetCollection>()) {
            if let id = collection.uuid { collectionsByID[id] = collection }
        }

        // Collections first, so snippets can join them. Existing ones are
        // reused as they are (only brought back from Trash); new ones are
        // created, then linked to their parents once all of them exist.
        var created: [UUID: SnippetCollection] = [:]
        for record in archive.collections {
            if let existing = collectionsByID[record.id] {
                existing.deletedAt = nil
            } else {
                let collection = SnippetCollection(
                    uuid: record.id, name: record.name, colorHex: record.colorHex,
                    colorHexDark: record.colorHexDark, iconName: record.iconName,
                    createdAt: record.createdAt, updatedAt: record.updatedAt, isFavorite: record.isFavorite
                )
                context.insert(collection)
                collectionsByID[record.id] = collection
                created[record.id] = collection
            }
        }
        for record in archive.collections {
            guard let collection = created[record.id], let parentID = record.parentID else { continue }
            collection.parent = collectionsByID[parentID]
        }

        var summary = ImportSummary()
        var standingChoice: ConflictChoice?
        var written: [(record: SnippetArchive.SnippetRecord, snippet: Snippet)] = []
        var replacedFiles: [String] = []

        for record in archive.snippets {
            guard let existing = snippetsByID[record.id] else {
                let snippet = Snippet(uuid: record.id)
                context.insert(snippet)
                replacedFiles += overwrite(snippet, with: record, collections: collectionsByID, in: context)
                snippetsByID[record.id] = snippet
                written.append((record, snippet))
                summary.added += 1
                continue
            }

            let choice: ConflictChoice
            if let standingChoice {
                choice = standingChoice
            } else {
                let resolution = await resolve(
                    ImportConflict(id: record.id, title: existing.title, isInTrash: existing.isDeleted)
                )
                if resolution.applyToAll { standingChoice = resolution.choice }
                choice = resolution.choice
            }

            if choice == .stop {
                summary.stopped = true
                break
            }
            if choice == .skip {
                summary.skipped += 1
                continue
            }
            replacedFiles += overwrite(existing, with: record, collections: collectionsByID, in: context)
            forgetTrust(record.id)
            written.append((record, existing))
            summary.replaced += 1
        }

        // Connections last: a dependency may appear later in the file. Ids that
        // resolve to nothing (a snippet never written because of Stop) drop out.
        for (record, snippet) in written {
            snippet.dependencies = record.dependencyIDs.compactMap { snippetsByID[$0] }
        }

        try context.save()
        replacedFiles.forEach(removeMedia)
        return summary
    }

    /// Copies every imported field onto `snippet` and swaps its attachments.
    /// Returns the file names of attachments it removed, for deletion after
    /// the save — a failed save must not have destroyed the user's files.
    private func overwrite(
        _ snippet: Snippet,
        with record: SnippetArchive.SnippetRecord,
        collections: [UUID: SnippetCollection],
        in context: ModelContext
    ) -> [String] {
        snippet.title = record.title
        snippet.snippetDescription = record.description
        snippet.language = record.language
        snippet.code = record.code
        snippet.createdAt = record.createdAt
        snippet.updatedAt = record.updatedAt
        snippet.isFavorite = record.isFavorite
        snippet.copyCount = record.copyCount
        snippet.deletedAt = nil
        snippet.paramConfigs = record.paramConfigs
        snippet.activeParamConfigID = record.activeParamConfigID
        snippet.collections = record.collectionIDs.compactMap { collections[$0] }

        let removed = snippet.mediaItems.map(\.fileName)
        snippet.mediaItems.forEach(context.delete)

        var items: [MediaItem] = []
        for media in record.media {
            // An attachment that cannot be written is dropped, not fatal.
            guard let name = try? writeMedia(media.data, media.fileExtension.lowercased()) else { continue }
            let item = MediaItem(fileName: name, kind: MediaManager.kind(for: URL(fileURLWithPath: name)), addedAt: media.addedAt)
            context.insert(item)
            items.append(item)
        }
        snippet.mediaItems = items
        return removed
    }
}
