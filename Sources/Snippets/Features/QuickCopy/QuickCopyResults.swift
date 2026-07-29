import Foundation

/// Ranking and sectioning for the quick-copy panel.
///
/// Pure by construction: it works over lightweight value projections rather
/// than `Snippet`, so it needs no `ModelContainer` and is fully unit-testable.
/// This mirrors `SnippetQueryFilter`, whose match predicate it reuses so the
/// panel and Shortcuts find the same snippets for the same text.
enum QuickCopyResults {

    /// Value projection of a snippet — every field the ranking needs, nothing more.
    struct Candidate {
        let title: String
        let description: String
        let language: String
        let isFavorite: Bool
        let copyCount: Int
        let updatedAt: Date
        /// Names of the collections the snippet belongs to; may be empty.
        let collectionNames: [String]
    }

    /// A run of results under an optional heading. `title` is nil for the
    /// scopes that present one flat list.
    struct Section<T> {
        let title: String?
        let items: [T]
    }

    /// Heading for snippets that belong to no collection. Sorted last.
    static let ungroupedTitle = "Ungrouped"

    static func sections<T>(
        _ items: [T],
        scope: QuickCopyScope,
        query: String,
        projection: (T) -> Candidate
    ) -> [Section<T>] {
        let matching = items.filter { item in
            let candidate = projection(item)
            guard SnippetQueryFilter.matches(
                title: candidate.title,
                description: candidate.description,
                language: candidate.language,
                query: query
            ) else { return false }

            switch scope {
            case .favorites: return candidate.isFavorite
            case .frequent: return candidate.copyCount > 0
            case .recent, .all: return true
            }
        }

        guard !matching.isEmpty else { return [] }

        switch scope {
        case .favorites, .recent:
            return [Section(title: nil, items: byRecency(matching, projection))]
        case .frequent:
            return [Section(title: nil, items: byCopyCount(matching, projection))]
        case .all:
            return byCollection(matching, projection)
        }
    }

    /// Every item in display order, ignoring section boundaries. The panel's
    /// selection index addresses this flat list.
    static func flattened<T>(_ sections: [Section<T>]) -> [T] {
        sections.flatMap(\.items)
    }

    // MARK: - Orderings
    //
    // Each ordering ends in a title comparison so equal keys never produce a
    // nondeterministic list — the panel must not reshuffle between openings.

    private static func byRecency<T>(_ items: [T], _ projection: (T) -> Candidate) -> [T] {
        items.sorted { left, right in
            let a = projection(left), b = projection(right)
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return isBefore(a.title, b.title)
        }
    }

    private static func byCopyCount<T>(_ items: [T], _ projection: (T) -> Candidate) -> [T] {
        items.sorted { left, right in
            let a = projection(left), b = projection(right)
            if a.copyCount != b.copyCount { return a.copyCount > b.copyCount }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return isBefore(a.title, b.title)
        }
    }

    /// A snippet can belong to several collections, or none. It is filed under
    /// the alphabetically first of its collections so it appears exactly once;
    /// listing it in every collection would make the same snippet show up
    /// repeatedly in a list whose whole purpose is a single quick pick.
    private static func byCollection<T>(
        _ items: [T],
        _ projection: (T) -> Candidate
    ) -> [Section<T>] {
        var buckets: [String: [T]] = [:]
        for item in items {
            let names = projection(item).collectionNames.sorted(by: isBefore)
            buckets[names.first ?? ungroupedTitle, default: []].append(item)
        }

        var headings = buckets.keys.filter { $0 != ungroupedTitle }.sorted(by: isBefore)
        if buckets[ungroupedTitle] != nil { headings.append(ungroupedTitle) }

        return headings.map { heading in
            let contents = (buckets[heading] ?? []).sorted { left, right in
                isBefore(projection(left).title, projection(right).title)
            }
            return Section(title: heading, items: contents)
        }
    }

    /// Localized, case- and numeral-aware comparison, so "item2" sorts before
    /// "item10" and accented titles land where a reader expects.
    private static func isBefore(_ left: String, _ right: String) -> Bool {
        left.localizedStandardCompare(right) == .orderedAscending
    }
}
