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
    var title: String = ""
    var snippetDescription: String = ""
    var code: String = ""
    var detectedLanguage: SupportedLanguage = .unknown
    var manualLanguage: SupportedLanguage?
    var mediaItems: [MediaItem] = []
    var selectedCollectionIDs: Set<PersistentIdentifier> = []
    var saveErrorMessage: String?

    private var hasLoaded = false

    var effectiveLanguage: SupportedLanguage {
        manualLanguage ?? detectedLanguage
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func hasUnsavedData(mode: SnippetEditorMode) -> Bool {
        switch mode {
        case .create:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !snippetDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !mediaItems.isEmpty
        case .edit(let original):
            return title != original.title
                || snippetDescription != original.snippetDescription
                || code != original.code
                || mediaItems != original.mediaItems
        }
    }

    var lineCount: Int {
        max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
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
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let base = slug.isEmpty ? (isEditing ? "snippet" : "untitled") : slug
        return base + Self.fileExtension(for: effectiveLanguage)
    }

    func save(
        mode: SnippetEditorMode,
        availableCollections: [SnippetCollection],
        modelContext: ModelContext,
        onSave: (Snippet) throws -> Void
    ) -> Bool {
        guard canSave else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = snippetDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let snippet = Snippet(
                title: trimmedTitle,
                snippetDescription: trimmedDescription,
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

            do {
                try onSave(snippet)
                return true
            } catch {
                saveErrorMessage = error.localizedDescription
                return false
            }

        case .edit(let snippet):
            snippet.title = trimmedTitle
            snippet.snippetDescription = trimmedDescription
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
