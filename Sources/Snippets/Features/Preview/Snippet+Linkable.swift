import Foundation
import SwiftData

extension Snippet: LinkableSnippet {
    var linkID: PersistentIdentifier { persistentModelID }
    var linkTitle: String { title }
    var linkLanguage: SupportedLanguage { SupportedLanguage(rawValue: language) ?? .unknown }
    var linkCode: String { code }
    var linkDependencies: [Snippet] { dependencies }
}
