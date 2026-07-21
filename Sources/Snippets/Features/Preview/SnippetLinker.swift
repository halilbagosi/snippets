import Foundation

/// Anything that can participate in preview linking. Production feeds
/// SwiftData `Snippet`s; tests feed plain structs.
protocol LinkableSnippet {
    associatedtype ID: Hashable
    var linkID: ID { get }
    var linkTitle: String { get }
    var linkLanguage: SupportedLanguage { get }
    var linkCode: String { get }
    var linkDependencies: [Self] { get }
}

/// One resolved contribution to a combined preview.
struct LinkedSource: Equatable {
    let language: SupportedLanguage
    let code: String
}

/// Flattens a snippet's dependency graph into the ordered sources its
/// preview engine consumes: helpers first (post-order), entry last, each
/// snippet at most once, cycles broken by the visited set. Dependencies
/// whose language cannot contribute to the entry's engine are dropped and
/// reported by title; their own dependencies are not traversed.
enum SnippetLinker {
    struct Resolution: Equatable {
        let sources: [LinkedSource]
        let excluded: [String]
    }

    static func resolve<S: LinkableSnippet>(entry: S) -> Resolution {
        var visited: Set<S.ID> = [entry.linkID]
        var sources: [LinkedSource] = []
        var excluded: [String] = []

        func visit(_ node: S) {
            for dep in node.linkDependencies {
                guard !visited.contains(dep.linkID) else { continue }
                visited.insert(dep.linkID)
                guard canContribute(dep.linkLanguage, toEntry: entry.linkLanguage) else {
                    excluded.append(dep.linkTitle)
                    continue
                }
                visit(dep)
                sources.append(LinkedSource(language: dep.linkLanguage, code: dep.linkCode))
            }
        }
        visit(entry)
        sources.append(LinkedSource(language: entry.linkLanguage, code: entry.linkCode))
        return Resolution(sources: sources, excluded: excluded)
    }

    /// Groups a gallery list into card stacks: a snippet that another list
    /// member depends on is tucked behind that member's card instead of
    /// appearing top-level. `connected` is the entry's dependency closure
    /// restricted to list members, in traversal order. Snippets orphaned by
    /// dependency cycles (everyone hidden, nobody visible) come back as
    /// plain entries so nothing ever disappears from the gallery.
    static func stacks<S: LinkableSnippet>(in snippets: [S]) -> [(entry: S, connected: [S])] {
        var present: [S.ID: S] = [:]
        for snippet in snippets where present[snippet.linkID] == nil {
            present[snippet.linkID] = snippet
        }
        var hidden: Set<S.ID> = []
        for snippet in snippets {
            for dep in snippet.linkDependencies where present[dep.linkID] != nil {
                hidden.insert(dep.linkID)
            }
        }

        var stacks: [(entry: S, connected: [S])] = []
        var shown: Set<S.ID> = []

        func appendStack(entry: S) {
            shown.insert(entry.linkID)
            var seen: Set<S.ID> = [entry.linkID]
            var connected: [S] = []
            func visit(_ node: S) {
                for dep in node.linkDependencies {
                    guard seen.insert(dep.linkID).inserted else { continue }
                    if let member = present[dep.linkID] {
                        connected.append(member)
                        shown.insert(member.linkID)
                    }
                    visit(dep)
                }
            }
            visit(entry)
            stacks.append((entry, connected))
        }

        for snippet in snippets where !hidden.contains(snippet.linkID) && !shown.contains(snippet.linkID) {
            appendStack(entry: snippet)
        }
        // Cycle fallback: mutually-connected members hid each other with no
        // visible entry. Front each cluster with its most entry-like member
        // (preview-richest language, ties by list order) and stack the rest.
        let leftovers = snippets.enumerated()
            .filter { !shown.contains($0.element.linkID) }
            .sorted { lhs, rhs in
                let l = entryAffinity(lhs.element.linkLanguage)
                let r = entryAffinity(rhs.element.linkLanguage)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
        for snippet in leftovers where !shown.contains(snippet.linkID) {
            appendStack(entry: snippet)
        }
        return stacks
    }

    /// The connected snippet that would make a stronger preview entry than
    /// the snippet being edited, if any — the editor surfaces it as a hint so
    /// users connect in the direction the preview engine expects. A candidate
    /// only qualifies when the reversed direction is actually previewable
    /// (the current entry's language can contribute to the candidate's).
    static func strongerEntry<S: LinkableSnippet>(
        thanEntryOf language: SupportedLanguage, among dependencies: [S]
    ) -> S? {
        let best = dependencies
            .filter { canContribute(language, toEntry: $0.linkLanguage) }
            .min { entryAffinity($0.linkLanguage) < entryAffinity($1.linkLanguage) }
        guard let best, entryAffinity(best.linkLanguage) < entryAffinity(language) else { return nil }
        return best
    }

    /// How suitable a language is to front a stack of mutually-connected
    /// snippets — lower is more entry-like. Support files (css) go last.
    static func entryAffinity(_ language: SupportedLanguage) -> Int {
        switch language {
        case .react: return 0
        case .typescript: return 1
        case .javascript: return 2
        case .html: return 3
        case .glsl, .metal, .swift: return 4
        case .css: return 9
        default: return 8
        }
    }

    /// Which dependency languages can feed an entry's preview engine.
    static func canContribute(_ dep: SupportedLanguage, toEntry entry: SupportedLanguage) -> Bool {
        switch entry {
        case .html, .react, .javascript, .typescript:
            return [.css, .javascript, .typescript, .react, .html].contains(dep)
        case .css:
            // A CSS entry previews against connected markup; extra CSS layers in.
            return [.html, .css].contains(dep)
        case .glsl: return dep == .glsl
        case .metal: return dep == .metal
        case .swift: return dep == .swift
        default: return false
        }
    }
}
