import Foundation
import SwiftData

extension Snippet: LinkableSnippet {
    var linkID: PersistentIdentifier { persistentModelID }
    var linkTitle: String { title }
    var linkLanguage: SupportedLanguage { SupportedLanguage(rawValue: language) ?? .unknown }
    var linkCode: String { code }
    var linkDependencies: [Snippet] { effectiveConnections }
}

extension Snippet {
    /// The other connections of every snippet this one is a connection of:
    /// connections of one snippet share access to each other, so a sibling
    /// counts as connected without being stored as a dependency. Each
    /// sibling appears once, in parent then dependency order; this snippet
    /// and its own direct connections are left out.
    ///
    /// `includingTrashed: false` skips trashed parents and trashed siblings —
    /// a trashed snippet no longer groups the live ones it used to connect.
    func siblingConnections(includingTrashed: Bool = false) -> [Snippet] {
        var seen: Set<PersistentIdentifier> = [persistentModelID]
        for dep in dependencies { seen.insert(dep.persistentModelID) }
        var result: [Snippet] = []
        for parent in dependents where includingTrashed || !parent.isDeleted {
            for sibling in parent.dependencies where includingTrashed || !sibling.isDeleted {
                guard seen.insert(sibling.persistentModelID).inserted else { continue }
                result.append(sibling)
            }
        }
        return result
    }

    /// Everything this snippet's preview, rating and gallery stack can draw
    /// on: its own connections first, then its siblings.
    var effectiveConnections: [Snippet] {
        dependencies + siblingConnections()
    }

    /// This snippet's live connection closure (connections, siblings, and
    /// theirs), excluding itself. Placing a snippet in a collection places
    /// these with it.
    var connectedClosure: [Snippet] {
        SnippetLinker.orderedDependencies(of: self).dependencies.filter { !$0.isDeleted }
    }
}
