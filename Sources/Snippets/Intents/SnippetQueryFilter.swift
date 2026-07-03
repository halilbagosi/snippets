import Foundation

/// Pure, dependency-free filtering shared by `SnippetEntityQuery` and
/// `FindSnippetsIntent`. Operates over lightweight value projections so it needs
/// no `ModelContainer` and is fully unit-testable.
enum SnippetQueryFilter {
    struct Candidate {
        let title: String
        let description: String
        let language: String
        let isFavorite: Bool
        let collectionUUIDs: Set<UUID>
    }

    /// Case-insensitive substring match across title, description, and language.
    /// An empty/whitespace query matches everything.
    static func matches(title: String, description: String, language: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return title.range(of: needle, options: .caseInsensitive) != nil
            || description.range(of: needle, options: .caseInsensitive) != nil
            || language.range(of: needle, options: .caseInsensitive) != nil
    }

    static func filter<T>(
        _ items: [T],
        query: String?,
        collectionUUID: UUID?,
        favoritesOnly: Bool,
        projection: (T) -> Candidate
    ) -> [T] {
        items.filter { item in
            let candidate = projection(item)
            if favoritesOnly && !candidate.isFavorite { return false }
            if let collectionUUID, !candidate.collectionUUIDs.contains(collectionUUID) { return false }
            if let query, !matches(title: candidate.title, description: candidate.description,
                                   language: candidate.language, query: query) {
                return false
            }
            return true
        }
    }
}
