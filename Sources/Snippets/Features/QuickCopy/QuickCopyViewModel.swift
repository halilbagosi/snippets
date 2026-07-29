import Foundation
import SwiftData
import Observation

/// State for the quick-copy panel. Owns the fetch and the SwiftData writes;
/// delegates every ordering, filtering and index decision to the pure types.
@Observable
@MainActor
final class QuickCopyViewModel {

    /// Remembers the scope across launches, per the design.
    private static let scopeDefaultsKey = "quickCopy.scope"

    var query: String = "" {
        didSet { guard query != oldValue else { return }; rebuild(resettingSelection: true) }
    }

    var scope: QuickCopyScope {
        didSet {
            guard scope != oldValue else { return }
            defaults.set(scope.rawValue, forKey: Self.scopeDefaultsKey)
            rebuild(resettingSelection: true)
        }
    }

    private(set) var sections: [QuickCopyResults.Section<Snippet>] = []
    private(set) var selectedIndex: Int = 0

    /// A clipboard capture awaiting a Save/Dismiss decision, or nil.
    /// At most one exists — a newer capture replaces an older one.
    var pendingCapture: ClipboardCapture.Candidate?

    private let context: ModelContext
    private let defaults: UserDefaults
    private var allSnippets: [Snippet] = []

    /// `defaults` is injectable so tests do not overwrite the real app's
    /// remembered scope just by running.
    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.scopeDefaultsKey)
        self.scope = stored.flatMap(QuickCopyScope.init(rawValue:)) ?? .favorites
        reload()
    }

    var flatResults: [Snippet] {
        QuickCopyResults.flattened(sections)
    }

    var selectedSnippet: Snippet? {
        let results = flatResults
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    /// Re-read the store. Called when the panel opens, because the panel is
    /// outside the scene graph and gets no automatic `@Query` invalidation.
    func reload() {
        let descriptor = FetchDescriptor<Snippet>(predicate: #Predicate { $0.deletedAt == nil })
        allSnippets = (try? context.fetch(descriptor)) ?? []
        rebuild(resettingSelection: false)
    }

    func move(by delta: Int) {
        selectedIndex = QuickCopySelection.moved(
            from: selectedIndex, by: delta, count: flatResults.count
        )
    }

    func select(_ snippet: Snippet) {
        guard let index = flatResults.firstIndex(where: { $0 === snippet }) else { return }
        selectedIndex = index
    }

    /// Copy the highlighted snippet's code and record it. Returns the snippet
    /// so the view can show its confirmation, or nil when nothing is selected.
    func copySelected() -> Snippet? {
        guard let snippet = selectedSnippet else { return nil }
        Clipboard.copy(snippet.code)
        SnippetStore.recordCopy(snippet, in: context)
        return snippet
    }

    func handleEscape() -> QuickCopySelection.EscapeOutcome {
        let outcome = QuickCopySelection.escape(query: query)
        if outcome == .clearQuery { query = "" }
        return outcome
    }

    private func rebuild(resettingSelection: Bool) {
        sections = QuickCopyResults.sections(allSnippets, scope: scope, query: query) { snippet in
            QuickCopyResults.Candidate(
                title: snippet.title,
                description: snippet.snippetDescription,
                language: snippet.language,
                isFavorite: snippet.isFavorite,
                copyCount: snippet.copyCount,
                updatedAt: snippet.updatedAt,
                collectionNames: snippet.collections.filter { $0.deletedAt == nil }.map(\.name)
            )
        }
        // A new query starts at the top; a background store change only pulls
        // the existing highlight back into range.
        selectedIndex = resettingSelection
            ? 0
            : QuickCopySelection.clamped(selectedIndex, count: flatResults.count)
    }
}
