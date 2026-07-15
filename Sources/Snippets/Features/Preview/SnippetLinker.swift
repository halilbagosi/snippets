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

    /// Which dependency languages can feed an entry's preview engine.
    static func canContribute(_ dep: SupportedLanguage, toEntry entry: SupportedLanguage) -> Bool {
        switch entry {
        case .html, .react, .javascript, .typescript:
            return [.css, .javascript, .typescript, .react, .html].contains(dep)
        case .glsl: return dep == .glsl
        case .metal: return dep == .metal
        case .swift: return dep == .swift
        default: return false
        }
    }
}
