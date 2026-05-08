import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct SnippetEditorView: View {
    enum Mode {
        case create
        case edit(Snippet)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let mode: Mode
    let availableCollections: [SnippetCollection]
    let onSave: (Snippet) throws -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var code: String = ""
    @State private var detectedLanguage: SupportedLanguage = .unknown
    @State private var manualLanguage: SupportedLanguage? = nil
    @State private var mediaItems: [MediaItem] = []
    @State private var selectedCollectionIDs: Set<PersistentIdentifier> = []
    @State private var saveErrorMessage: String? = nil

    @FocusState private var focus: Field?
    @State private var codeFocused: Bool = false

    enum Field: Hashable { case title, description }

    private var isEditingAnyField: Bool { focus != nil || codeFocused }

    private var theme: Theme { Theme.current(colorScheme) }
    private var effectiveLanguage: SupportedLanguage { manualLanguage ?? detectedLanguage }
    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lineCount: Int {
        max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }

    var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            DotGridBackground(lightModeStrength: 0.55).opacity(0.52).ignoresSafeArea()

            VStack(spacing: 0) {
                editorChrome

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        titleSection
                        descriptionSection
                        languageSection
                        collectionsSection
                        codeSection
                        mediaSection
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                editorStatusBar
            }
        }
        .frame(minWidth: 820, minHeight: 660)
        .onAppear {
            load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focus = .title
            }
        }
        .onChange(of: code) { _, newValue in
            detectedLanguage = LanguageDetector.detect(code: newValue)
        }
        .alert("Could not save snippet", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    private var editorChrome: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: effectiveLanguage.symbolName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: effectiveLanguage.accentHex) ?? theme.accent)
                Text(headerFilename)
                    .font(Mono.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("●")
                    .font(Mono.font(size: 8))
                    .foregroundStyle(theme.accent)
                    .opacity(canSave ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    }
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Text("cancel")
                    .font(Mono.font(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(Mono.font(size: 9, weight: .bold))
                    Text("⏎ \(isEditing ? "save" : "create")")
                        .font(Mono.font(size: 12, weight: .semibold))
                }
                .foregroundStyle(canSave ? .white : theme.textFaint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(canSave ? theme.accent : theme.inset)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(theme.surfaceElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
        }
    }

    private var headerFilename: String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let base = slug.isEmpty ? (isEditing ? "snippet" : "untitled") : slug
        return base + extensionFor(effectiveLanguage)
    }

    private func extensionFor(_ language: SupportedLanguage) -> String {
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

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("title")
            TextField("e.g. Procedural Noise Shader", text: $title)
                .textFieldStyle(.plain)
                .focused($focus, equals: .title)
                .font(Sans.font(size: 18, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(fieldBackground(focused: focus == .title))
                .contentShape(Rectangle())
                .onTapGesture { focus = .title }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("description")
            TextField("What does this snippet do?", text: $description, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($focus, equals: .description)
                .lineLimit(2...5)
                .font(Sans.font(size: 14))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(fieldBackground(focused: focus == .description))
                .contentShape(Rectangle())
                .onTapGesture { focus = .description }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("language")
            HStack(spacing: 10) {
                Menu {
                    Button("Auto-detect") { manualLanguage = nil }
                    Divider()
                    ForEach(SupportedLanguage.allCases) { language in
                        Button {
                            manualLanguage = language
                        } label: {
                            HStack {
                                Image(systemName: language.symbolName)
                                Text(language.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        LanguageBadge(language: effectiveLanguage)
                        if manualLanguage == nil {
                            Text("auto-detect")
                                .font(Mono.font(size: 11, weight: .medium))
                                .foregroundStyle(theme.textMuted)
                        }
                        Image(systemName: "chevron.down")
                            .font(Mono.font(size: 9, weight: .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(fieldBackground(focused: false))
                }
                .menuStyle(.button)
                .fixedSize()

                if manualLanguage != nil {
                    Button {
                        manualLanguage = nil
                    } label: {
                        Text("reset to auto")
                            .font(Mono.font(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
    }

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("code", trailing: AnyView(
                HStack(spacing: 6) {
                    Image(systemName: effectiveLanguage.symbolName)
                        .font(Mono.font(size: 10, weight: .semibold))
                    Text(effectiveLanguage.rawValue.lowercased())
                        .font(Mono.font(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color(hex: effectiveLanguage.accentHex) ?? theme.accent)
            ))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.canvasDeep)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(codeFocused ? theme.accent.opacity(0.6) : theme.border, lineWidth: 1)
                    }

                CodeEditor(
                    text: $code,
                    isFocused: $codeFocused,
                    language: effectiveLanguage,
                    theme: theme,
                    fontSize: 13,
                    minHeight: 240
                )
                .padding(2)
                .frame(minHeight: 260)

                if code.isEmpty && !codeFocused {
                    Text("// paste or type your code here…")
                        .font(Mono.font(size: 13))
                        .foregroundStyle(theme.comment)
                        .padding(.leading, 56)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("collections")
            if availableCollections.isEmpty {
                Text("No collections yet. Create one from the sidebar.")
                    .font(Mono.font(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(availableCollections) { collection in
                        let isSelected = selectedCollectionIDs.contains(collection.persistentModelID)
                        Button {
                            if isSelected {
                                selectedCollectionIDs.remove(collection.persistentModelID)
                            } else {
                                selectedCollectionIDs.insert(collection.persistentModelID)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                Text(collection.name.lowercased())
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(Mono.font(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : theme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? theme.accent : theme.surface)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(isSelected ? theme.accent.opacity(0.4) : theme.border, lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("attachments", trailing: AnyView(
                Text("optional")
                    .font(Mono.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textFaint)
            ))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        let imported = MediaManager.pickAndImport()
                        mediaItems.append(contentsOf: imported)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(Mono.font(size: 11, weight: .bold))
                            Text("attach image / video")
                                .font(Mono.font(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(theme.text)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(theme.border, lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)

                    if !mediaItems.isEmpty {
                        Text("\(mediaItems.count) attached")
                            .font(Mono.font(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                }

                if !mediaItems.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(mediaItems) { item in
                            MediaThumbnail(item: item) {
                                if let index = mediaItems.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) {
                                    let removed = mediaItems.remove(at: index)
                                    MediaManager.deleteFile(for: removed)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var editorStatusBar: some View {
        StatusBar(segments: [
            .init(icon: "circle.fill", label: isEditingAnyField ? "editing" : "idle", tint: isEditingAnyField ? theme.accent : theme.textFaint),
            .init(label: "ln \(lineCount)"),
            .init(label: "col 1"),
            .init(label: effectiveLanguage.rawValue.lowercased(), tint: Color(hex: effectiveLanguage.accentHex)),
            .init(icon: "paperclip", label: "\(mediaItems.count)"),
            .init(icon: "folder", label: "\(selectedCollectionIDs.count)")
        ])
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? theme.accent.opacity(0.6) : theme.border, lineWidth: 1)
            }
    }

    private func load() {
        if case .edit(let snippet) = mode {
            title = snippet.title
            description = snippet.snippetDescription
            code = snippet.code
            mediaItems = snippet.mediaItems
            selectedCollectionIDs = Set(snippet.collections.map(\.persistentModelID))
            if let lang = SupportedLanguage(rawValue: snippet.language) {
                manualLanguage = lang
                detectedLanguage = lang
            } else {
                detectedLanguage = LanguageDetector.detect(code: snippet.code)
            }
        } else {
            detectedLanguage = LanguageDetector.detect(code: code)
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

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
            for item in mediaItems { item.snippet = snippet }
            snippet.mediaItems = mediaItems
            let selectedCollections = availableCollections.filter { selectedCollectionIDs.contains($0.persistentModelID) }
            snippet.collections = selectedCollections
            for collection in selectedCollections {
                collection.updatedAt = .now
            }
            do {
                try onSave(snippet)
            } catch {
                saveErrorMessage = error.localizedDescription
                return
            }
            dismiss()
        case .edit(let snippet):
            snippet.title = trimmedTitle
            snippet.snippetDescription = trimmedDescription
            snippet.language = effectiveLanguage.rawValue
            snippet.code = code
            snippet.updatedAt = .now

            let existingIDs = Set(snippet.mediaItems.map { $0.persistentModelID })
            let newIDs = Set(mediaItems.map { $0.persistentModelID })

            for item in snippet.mediaItems where !newIDs.contains(item.persistentModelID) {
                MediaManager.deleteFile(for: item)
                modelContext.delete(item)
            }
            for item in mediaItems where !existingIDs.contains(item.persistentModelID) {
                modelContext.insert(item)
                item.snippet = snippet
            }
            snippet.mediaItems = mediaItems

            let selectedCollections = availableCollections.filter { selectedCollectionIDs.contains($0.persistentModelID) }
            for collection in selectedCollections {
                collection.updatedAt = .now
            }
            snippet.collections = selectedCollections
            do {
                try modelContext.save()
                try onSave(snippet)
            } catch {
                saveErrorMessage = error.localizedDescription
                return
            }
            dismiss()
        }
    }
}

private struct MediaThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    let onRemove: () -> Void
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    #endif

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface)
                .overlay {
                    mediaContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: loadThumbnail)
    }

    @ViewBuilder
    private var mediaContent: some View {
        #if canImport(AppKit)
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if item.kind == .video {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
        #else
        Image(systemName: item.kind == .video ? "play.rectangle.fill" : "photo")
            .font(.system(size: 26))
            .foregroundStyle(.secondary)
        #endif
    }

    private func loadThumbnail() {
        #if canImport(AppKit)
        guard item.kind == .image, image == nil else { return }
        let url = MediaManager.resolvedURL(for: item.fileName)
        image = NSImage(contentsOf: url)
        #endif
    }
}
