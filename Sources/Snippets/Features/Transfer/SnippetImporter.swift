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
    /// Deletes an attachment file: a replaced one after the save succeeded, or
    /// one written by an import that then failed.
    var removeMedia: @MainActor (String) -> Void
    /// Drops preview permissions for a replaced snippet.
    var forgetTrust: @MainActor (UUID) -> Void

    /// Two phases. First every conflict is put to `resolve` — which is a
    /// window-modal dialog in production, so other saves can run while it is
    /// up — and nothing is mutated. Only once the last answer is in does the
    /// import touch the context, synchronously, so no other save can ever
    /// commit a half-applied import and a failure can still roll it all back.
    func apply(
        _ archive: SnippetArchive,
        to context: ModelContext,
        resolve: @MainActor (ImportConflict) async -> ConflictResolution
    ) async throws -> ImportSummary {
        // Ask phase.
        var plan: [UUID: ConflictChoice] = [:]
        var stopIndex: Int?
        var standingChoice: ConflictChoice?
        var existingByID = try snippetsByID(in: context)
        for (index, record) in archive.snippets.enumerated() {
            guard let existing = existingByID[record.id] else { continue }
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
                stopIndex = index
                break
            }
            plan[record.id] = choice
        }
        existingByID = [:]   // stale after the suspensions; the apply phase re-reads

        // Apply phase: no suspension point from here on.
        // Files written during this call. If anything fails the context is
        // rolled back, so these would be orphans.
        var newFiles: [String] = []
        do {
            return try commit(archive, to: context, plan: plan, stopIndex: stopIndex, newFiles: &newFiles)
        } catch {
            context.rollback()
            newFiles.forEach(removeMedia)
            throw error
        }
    }

    private func snippetsByID(in context: ModelContext) throws -> [UUID: Snippet] {
        var result: [UUID: Snippet] = [:]
        for snippet in try context.fetch(FetchDescriptor<Snippet>()) {
            if let id = snippet.uuid { result[id] = snippet }
        }
        return result
    }

    /// Everything after the last answer. Synchronous on purpose.
    private func commit(
        _ archive: SnippetArchive,
        to context: ModelContext,
        plan: [UUID: ConflictChoice],
        stopIndex: Int?,
        newFiles: inout [String]
    ) throws -> ImportSummary {
        var snippetsByID = try snippetsByID(in: context)
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
        var written: [(record: SnippetArchive.SnippetRecord, snippet: Snippet)] = []
        var replacedFiles: [String] = []
        var distrusted: [UUID] = []   // replaced snippets and their dependents

        for (index, record) in archive.snippets.enumerated() {
            if let stopIndex, index >= stopIndex {
                summary.stopped = true
                break
            }
            guard let existing = snippetsByID[record.id] else {
                let snippet = Snippet(uuid: record.id)
                context.insert(snippet)
                replacedFiles += try overwrite(snippet, with: record, collections: collectionsByID, in: context, newFiles: &newFiles)
                snippetsByID[record.id] = snippet
                written.append((record, snippet))
                summary.added += 1
                continue
            }

            // A snippet that appeared while the dialog was up was never asked
            // about; the safe answer is to leave it alone.
            guard plan[record.id] == .replace else {
                summary.skipped += 1
                continue
            }
            // Its code runs inside its dependents' combined previews, so their
            // approvals go too.
            distrusted.append(record.id)
            distrusted += existing.dependents.compactMap(\.uuid)
            replacedFiles += try overwrite(existing, with: record, collections: collectionsByID, in: context, newFiles: &newFiles)
            written.append((record, existing))
            summary.replaced += 1
        }

        // Connections last: a dependency may appear later in the file. Ids that
        // resolve to nothing (a snippet never written because of Stop) drop out.
        for (record, snippet) in written {
            snippet.dependencies = record.dependencyIDs.compactMap { snippetsByID[$0] }
        }

        try context.save()
        // Only now that the import is committed: drop the replaced snippets'
        // (and their dependents') trust and the old files.
        var seen = Set<UUID>()
        distrusted.filter { seen.insert($0).inserted }.forEach(forgetTrust)
        replacedFiles.forEach(removeMedia)
        return summary
    }

    /// Copies every imported field onto `snippet` and swaps its attachments.
    /// Returns the file names of attachments it removed, for deletion after
    /// the save — a failed save must not have destroyed the user's files.
    /// Every file it writes is appended to `newFiles` at once, so the caller
    /// can clean up if a later write or the save fails.
    private func overwrite(
        _ snippet: Snippet,
        with record: SnippetArchive.SnippetRecord,
        collections: [UUID: SnippetCollection],
        in context: ModelContext,
        newFiles: inout [String]
    ) throws -> [String] {
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
            let name = try writeMedia(media.data, media.fileExtension.lowercased())
            newFiles.append(name)
            let item = MediaItem(fileName: name, kind: MediaManager.kind(for: URL(fileURLWithPath: name)), addedAt: media.addedAt)
            context.insert(item)
            items.append(item)
        }
        snippet.mediaItems = items
        return removed
    }
}
