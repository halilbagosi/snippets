import Foundation
import Observation
import SwiftData

enum SnippetEditorMode {
    case create(preselectedCollectionID: PersistentIdentifier? = nil)
    case edit(Snippet)
}

@MainActor
@Observable
final class SnippetEditorViewModel {
    var title: String = "" {
        didSet { updateTitleCaches() }
    }
    var snippetDescription: String = "" {
        didSet { trimmedSnippetDescription = snippetDescription.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    var code: String = "" {
        didSet { updateCodeCaches() }
    }
    var detectedLanguage: SupportedLanguage = .unknown
    var manualLanguage: SupportedLanguage?
    var mediaItems: [MediaItem] = []
    var selectedCollectionIDs: Set<PersistentIdentifier> = []
    /// Snippets this one depends on for combined previews, in user order.
    var dependencies: [Snippet] = []
    var saveErrorMessage: String?

    private var hasLoaded = false
    private var trimmedTitle = ""
    private var trimmedCode = ""
    private var trimmedSnippetDescription = ""
    private var titleSlug = ""
    private(set) var lineCount: Int = 1

    var effectiveLanguage: SupportedLanguage {
        manualLanguage ?? detectedLanguage
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty && !trimmedCode.isEmpty
    }

    func hasUnsavedData(mode: SnippetEditorMode) -> Bool {
        switch mode {
        case .create:
            return !trimmedTitle.isEmpty
                || !trimmedCode.isEmpty
                || !trimmedSnippetDescription.isEmpty
                || !mediaItems.isEmpty
        case .edit(let original):
            return title != original.title
                || snippetDescription != original.snippetDescription
                || code != original.code
                || mediaItems != original.mediaItems
                || dependencies.map(\.persistentModelID) != original.dependencies.map(\.persistentModelID)
        }
    }

    func load(mode: SnippetEditorMode) {
        guard !hasLoaded else { return }
        hasLoaded = true

        if case .edit(let snippet) = mode {
            title = snippet.title
            snippetDescription = snippet.snippetDescription
            code = snippet.code
            mediaItems = snippet.mediaItems
            selectedCollectionIDs = Set(snippet.collections.map(\.persistentModelID))
            dependencies = snippet.dependencies

            if let language = SupportedLanguage(rawValue: snippet.language) {
                manualLanguage = language
                detectedLanguage = language
            } else {
                detectedLanguage = LanguageDetector.detect(code: snippet.code)
            }
        } else {
            if case .create(let preselectedCollectionID) = mode, let id = preselectedCollectionID {
                selectedCollectionIDs.insert(id)
            }
            detectedLanguage = LanguageDetector.detect(code: code)
        }
    }

    func updateDetectedLanguage(for newCode: String) {
        detectedLanguage = LanguageDetector.detect(code: newCode)
    }

    func selectManualLanguage(_ language: SupportedLanguage) {
        manualLanguage = language
    }

    func resetManualLanguage() {
        manualLanguage = nil
    }

    func toggleCollection(_ collection: SnippetCollection) {
        let id = collection.persistentModelID
        if selectedCollectionIDs.contains(id) {
            selectedCollectionIDs.remove(id)
        } else {
            selectedCollectionIDs.insert(id)
        }
    }

    func addDependency(_ snippet: Snippet) {
        guard !dependencies.contains(where: { $0.persistentModelID == snippet.persistentModelID }) else { return }
        dependencies.append(snippet)
    }

    func removeDependency(_ snippet: Snippet) {
        dependencies.removeAll { $0.persistentModelID == snippet.persistentModelID }
    }

    /// Whether `snippet` can be offered in the connections picker: not the
    /// snippet being edited and not already a dependency.
    func isDependencyCandidate(_ snippet: Snippet, mode: SnippetEditorMode) -> Bool {
        if case .edit(let original) = mode,
           original.persistentModelID == snippet.persistentModelID {
            return false
        }
        return !dependencies.contains { $0.persistentModelID == snippet.persistentModelID }
    }

    func attachMedia(using mediaManager: any MediaManaging) {
        mediaItems.append(contentsOf: mediaManager.pickAndImport())
    }

    func removeMediaItem(_ item: MediaItem, using mediaManager: any MediaManaging) {
        guard let index = mediaItems.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) else {
            return
        }

        let removed = mediaItems.remove(at: index)
        mediaManager.deleteFile(for: removed)
    }

    func headerFilename(isEditing: Bool) -> String {
        let base = titleSlug.isEmpty ? (isEditing ? "snippet" : "untitled") : titleSlug
        return base + Self.fileExtension(for: effectiveLanguage)
    }

    func save(
        mode: SnippetEditorMode,
        availableCollections: [SnippetCollection],
        modelContext: ModelContext,
        onSave: (Snippet) throws -> Void
    ) -> Bool {
        guard canSave else { return false }

        switch mode {
        case .create:
            let snippet = Snippet(
                title: trimmedTitle,
                snippetDescription: trimmedSnippetDescription,
                language: effectiveLanguage.rawValue,
                code: code,
                createdAt: .now,
                updatedAt: .now
            )

            for item in mediaItems {
                item.snippet = snippet
            }
            snippet.mediaItems = mediaItems
            let selectedCollections = selectedCollections(from: availableCollections)
            snippet.collections = selectedCollections
            for collection in selectedCollections {
                collection.updatedAt = .now
            }
            snippet.dependencies = dependencies

            do {
                try onSave(snippet)
                return true
            } catch {
                saveErrorMessage = error.localizedDescription
                return false
            }

        case .edit(let snippet):
            snippet.title = trimmedTitle
            snippet.snippetDescription = trimmedSnippetDescription
            snippet.language = effectiveLanguage.rawValue
            snippet.code = code
            snippet.updatedAt = .now

            let existingIDs = Set(snippet.mediaItems.map(\.persistentModelID))
            let newIDs = Set(mediaItems.map(\.persistentModelID))

            for item in snippet.mediaItems where !newIDs.contains(item.persistentModelID) {
                modelContext.delete(item)
            }
            for item in mediaItems where !existingIDs.contains(item.persistentModelID) {
                modelContext.insert(item)
                item.snippet = snippet
            }
            snippet.mediaItems = mediaItems

            let selectedCollections = selectedCollections(from: availableCollections)
            for collection in selectedCollections {
                collection.updatedAt = .now
            }
            snippet.collections = selectedCollections
            snippet.dependencies = dependencies

            do {
                try modelContext.save()
                try onSave(snippet)
                return true
            } catch {
                saveErrorMessage = error.localizedDescription
                return false
            }
        }
    }

    private func selectedCollections(from collections: [SnippetCollection]) -> [SnippetCollection] {
        collections.filter { selectedCollectionIDs.contains($0.persistentModelID) }
    }

    private func updateTitleCaches() {
        trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleSlug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func updateCodeCaches() {
        trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        lineCount = max(code.utf8.reduce(0) { count, byte in
            count + (byte == 0x0A ? 1 : 0)
        } + 1, 1)
    }

    private static func fileExtension(for language: SupportedLanguage) -> String {
        switch language {
        case .swift: return ".swift"
        case .glsl: return ".glsl"
        case .metal: return ".metal"
        case .hlsl: return ".hlsl"
        case .kotlin: return ".kt"
        case .rust: return ".rs"
        case .go: return ".go"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .react: return ".jsx"
        case .css: return ".css"
        case .html: return ".html"
        case .json: return ".json"
        case .cpp: return ".cpp"
        case .unknown: return ".txt"
        }
    }
}
