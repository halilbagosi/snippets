import Foundation

/// Text search shared by every surface that searches snippets — the gallery,
/// Trash, the quick-copy panel and Shortcuts — so a query means the same thing
/// everywhere. The query is split into words; every word must appear in at
/// least one field, ignoring case and accents, so word order and contiguity
/// don't matter ("swift parser" finds a Swift snippet titled "JSON parser").
enum SnippetSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The words of a query. Empty for a blank query.
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every term occurs in at least one field. No terms matches.
    static func matches(terms: [String], in fields: [String]) -> Bool {
        terms.allSatisfy { term in
            fields.contains { contains($0, term) }
        }
    }

    /// Compares through NSString: Swift's `String.range(of:options:)` is about
    /// 20x slower on large native strings, and the gallery searches every
    /// snippet's full code on each keystroke.
    private static func contains(_ haystack: String, _ term: String) -> Bool {
        (haystack as NSString).range(of: term, options: options).location != NSNotFound
    }
}

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

    /// Every word of the query in title, description, or language (see
    /// `SnippetSearch`). An empty/whitespace query matches everything.
    static func matches(title: String, description: String, language: String, query: String) -> Bool {
        SnippetSearch.matches(terms: SnippetSearch.terms(query), in: [title, description, language])
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
