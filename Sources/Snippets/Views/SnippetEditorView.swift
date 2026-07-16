import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct SnippetEditorView: View {
    typealias Mode = SnippetEditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let mode: Mode
    let availableCollections: [SnippetCollection]
    let availableSnippets: [Snippet]
    let onSave: (Snippet) throws -> Void
    var onRequestDismiss: (() -> Void)? = nil
    private let mediaManager: any MediaManaging

    @State private var viewModel = SnippetEditorViewModel()

    @FocusState private var focus: Field?
    @State private var codeFocused: Bool = false
    @State private var isPresentingCancelConfirm: Bool = false
    @State private var languageDetectionTask: Task<Void, Never>? = nil
    @State private var showValidationFeedback: Bool = false
    @State private var validationShake: Bool = false
    @State private var isAddingConnection: Bool = false
    @State private var connectionSearch: String = ""

    enum Field: Hashable { case title, description }

    init(
        mode: Mode,
        availableCollections: [SnippetCollection],
        availableSnippets: [Snippet] = [],
        mediaManager: any MediaManaging = MediaManager.shared,
        onRequestDismiss: (() -> Void)? = nil,
        onSave: @escaping (Snippet) throws -> Void
    ) {
        self.mode = mode
        self.availableCollections = availableCollections
        self.availableSnippets = availableSnippets
        self.mediaManager = mediaManager
        self.onRequestDismiss = onRequestDismiss
        self.onSave = onSave
    }

    private var isEditingAnyField: Bool { focus != nil || codeFocused }

    private var theme: Theme { Theme.current(colorScheme) }
    private var effectiveLanguage: SupportedLanguage { viewModel.effectiveLanguage }
    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var canSave: Bool { viewModel.canSave }
    private var lineCount: Int { viewModel.lineCount }

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
                        connectionsSection
                        codeSection
                        mediaSection
                    }
                    .padding(DSToken.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                editorStatusBar
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            viewModel.load(mode: mode)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                focus = .title
            }
        }
        .onChange(of: viewModel.code) { _, newValue in
            debounceLanguageDetection(for: newValue)
        }
        .alert("Could not save snippet", isPresented: Binding(
            get: { viewModel.saveErrorMessage != nil },
            set: { if !$0 { viewModel.saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.saveErrorMessage = nil }
        } message: {
            Text(viewModel.saveErrorMessage ?? "Unknown error")
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedData(mode: mode))
        .onReceive(NotificationCenter.default.publisher(for: .init("AttemptDismissEditor"))) { _ in
            if viewModel.hasUnsavedData(mode: mode) {
                isPresentingCancelConfirm = true
            } else {
                if let onRequestDismiss {
                    onRequestDismiss()
                } else {
                    dismiss()
                }
            }
        }
        .onDisappear {
            languageDetectionTask?.cancel()
        }
    }

    private var editorChrome: some View {
        VStack(spacing: 8) {
            if showValidationFeedback && !canSave {
                Text("Title and code are required to save.")
                    .font(Sans.font(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: effectiveLanguage.symbolName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: effectiveLanguage.accentHex) ?? theme.accent)
                Text(viewModel.headerFilename(isEditing: isEditing))
                    .font(Mono.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("●")
                    .font(Mono.font(size: 8))
                    .foregroundStyle(theme.accent)
                    .opacity(canSave ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: (Color(hex: effectiveLanguage.accentHex) ?? theme.accent).opacity(0.1),
                shadowRadius: 4,
                shadowY: 2
            )

            Spacer(minLength: 8)

            Button {
                if viewModel.hasUnsavedData(mode: mode) {
                    isPresentingCancelConfirm = true
                } else {
                    if let onRequestDismiss {
                        onRequestDismiss()
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Text("cancel")
                    .font(Mono.font(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                interactive: true,
                shadowRadius: 4,
                shadowY: 2
            )
            .keyboardShortcut(.cancelAction)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $isPresentingCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { 
                    if let onRequestDismiss {
                        onRequestDismiss()
                    } else {
                        dismiss()
                    }
                }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your snippet has unsaved content. Discard it?")
            }

            Button {
                if canSave {
                    save()
                } else {
                    withAnimation { showValidationFeedback = true }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                        validationShake.toggle()
                    }
                    if viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        focus = .title
                    } else if viewModel.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        codeFocused = true
                    }
                }
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(canSave ? theme.accent : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: canSave ? theme.accent.opacity(0.2) : nil,
                interactive: true,
                shadowRadius: 4,
                shadowY: 2
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlassSurface(
            in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 0, style: .continuous),
            shadowRadius: 8,
            shadowY: 4
        )
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("title")
            TextField("e.g. Procedural Noise Shader", text: $viewModel.title)
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
        .offset(x: validationShake && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 5 : 0)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("description")
            TextField("What does this snippet do?", text: $viewModel.snippetDescription, axis: .vertical)
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
                    Button("Auto-detect") { viewModel.resetManualLanguage() }
                    Divider()
                    ForEach(SupportedLanguage.allCases) { language in
                        Button {
                            viewModel.selectManualLanguage(language)
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
                        if viewModel.manualLanguage == nil {
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
                    .liquidGlassSurface(
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                        interactive: true,
                        borderOpacity: colorScheme == .dark ? 0.16 : 0.36
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if viewModel.manualLanguage != nil {
                    Button {
                        viewModel.resetManualLanguage()
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
            SectionHeader("code") {
                HStack(spacing: 6) {
                    Image(systemName: effectiveLanguage.symbolName)
                        .font(Mono.font(size: 10, weight: .semibold))
                    Text(effectiveLanguage.rawValue.lowercased())
                        .font(Mono.font(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color(hex: effectiveLanguage.accentHex) ?? theme.accent)
            }
            ZStack(alignment: .topLeading) {
                // No padding here: an inset would hold the line-number gutter's
                // square corners away from the rounded clip below, so they
                // wouldn't follow the container's radius. Flush = clip rounds them.
                CodeEditor(
                    text: $viewModel.code,
                    isFocused: $codeFocused,
                    language: effectiveLanguage,
                    theme: theme,
                    fontSize: 13,
                    minHeight: 160
                )
                .frame(minHeight: 180)

                if viewModel.code.isEmpty && !codeFocused {
                    Text("// paste or type your code here…")
                        .font(Mono.font(size: 13))
                        .foregroundStyle(theme.comment)
                        .padding(.leading, 56)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                tint: (Color(hex: effectiveLanguage.accentHex) ?? theme.accent).opacity(0.06),
                borderOpacity: codeFocused ? 0.45 : nil,
                shadowRadius: 8,
                shadowY: 4
            )
            .overlay {
                if codeFocused {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.accent.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .offset(x: validationShake && viewModel.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 5 : 0)
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
                        let isSelected = viewModel.selectedCollectionIDs.contains(collection.persistentModelID)
                        let collectionColor = collection.displayColor
                        Button {
                            viewModel.toggleCollection(collection)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(collectionColor)
                                CollectionIconView(
                                    iconName: collection.displayIconName,
                                    color: collectionColor,
                                    size: 14,
                                    isSelected: isSelected
                                )
                                Text(collection.name.lowercased())
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(Mono.font(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? collectionColor : theme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? collectionColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : theme.surface)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(isSelected ? collectionColor.opacity(0.4) : theme.border, lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// How to author snippets so combined previews actually run — written
    /// from the preview engine's real constraints (see WebPreviewHTMLBuilder).
    private var connectionsHint: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("connections run before this snippet in one shared preview:")
            Text("• reference a connection by the name it defines — import lines are ignored")
            Text("• keep a component's css as its own connected css snippet (import \"./x.css\" is dropped)")
            Text("• npm packages (framer-motion, gsap…) can't load — only react itself is bundled")
            Text("• web languages link with web entries; swift with swift; glsl with glsl")
        }
        .font(Mono.font(size: 10))
        .foregroundStyle(theme.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.surface.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
    }

    /// Snippets this one depends on for combined previews (see SnippetLinker).
    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("connections") {
                Text("optional")
                    .font(Mono.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }

            if !viewModel.dependencies.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(viewModel.dependencies) { dependency in
                        Button {
                            viewModel.removeDependency(dependency)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(Mono.font(size: 9, weight: .semibold))
                                Text(dependency.title.lowercased())
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "xmark")
                                    .font(Mono.font(size: 8, weight: .bold))
                            }
                            .font(Mono.font(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.accent.opacity(colorScheme == .dark ? 0.22 : 0.12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Remove connection")
                    }
                }
            }

            if isAddingConnection {
                VStack(alignment: .leading, spacing: 6) {
                    connectionsHint
                    TextField("search snippets", text: $connectionSearch)
                        .textFieldStyle(.plain)
                        .font(Mono.font(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(theme.border, lineWidth: 1)
                                }
                        }
                    if connectionCandidates.isEmpty {
                        Text("no matching snippets")
                            .font(Mono.font(size: 11))
                            .foregroundStyle(theme.textMuted)
                            .padding(.horizontal, 4)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(connectionCandidates.prefix(20)) { candidate in
                                    Button {
                                        viewModel.addDependency(candidate)
                                        connectionSearch = ""
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus.circle")
                                                .foregroundStyle(theme.accent)
                                            Text(candidate.title)
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text(candidate.language.lowercased())
                                                .foregroundStyle(theme.textMuted)
                                        }
                                        .font(Mono.font(size: 11))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }

            Button {
                isAddingConnection.toggle()
                if !isAddingConnection { connectionSearch = "" }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isAddingConnection ? "chevron.up" : "plus")
                    Text(isAddingConnection ? "done" : "add connection")
                }
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var connectionCandidates: [Snippet] {
        let base = availableSnippets.filter { viewModel.isDependencyCandidate($0, mode: mode) }
        guard !connectionSearch.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(connectionSearch) }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("attachments") {
                Text("optional")
                    .font(Mono.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textFaint)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.attachMedia(using: mediaManager)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(Mono.font(size: 11, weight: .bold))
                            Text("attach image / video")
                                .font(Mono.font(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassSurface(
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                        interactive: true,
                        shadowRadius: 4,
                        shadowY: 2
                    )

                    if !viewModel.mediaItems.isEmpty {
                        Text("\(viewModel.mediaItems.count) attached")
                            .font(Mono.font(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                }

                if !viewModel.mediaItems.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.mediaItems) { item in
                            MediaThumbnail(item: item) {
                                viewModel.removeMediaItem(item, using: mediaManager)
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
            .init(icon: "paperclip", label: "\(viewModel.mediaItems.count)"),
            .init(icon: "folder", label: "\(viewModel.selectedCollectionIDs.count)")
        ])
    }

    private func fieldBackground(focused: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.clear)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                    borderOpacity: focused ? 0.5 : nil,
                    shadowRadius: focused ? 6 : 3,
                    shadowY: focused ? 3 : 1
                )
            if focused {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.accent.opacity(0.5), lineWidth: 1)
            }
        }
    }

    private func save() {
        let didSave = viewModel.save(
            mode: mode,
            availableCollections: availableCollections,
            modelContext: modelContext,
            onSave: onSave
        )

        if didSave {
            if let onRequestDismiss {
                onRequestDismiss()
            } else {
                dismiss()
            }
        }
    }

    private func debounceLanguageDetection(for code: String) {
        languageDetectionTask?.cancel()

        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.updateDetectedLanguage(for: code)
            return
        }

        languageDetectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.updateDetectedLanguage(for: code)
        }
    }
}

private struct MediaThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    let onRemove: () -> Void
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    @State private var imageLoadTask: Task<Void, Never>? = nil
    @State private var loadFailed: Bool = false
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
            .padding(DSToken.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: loadThumbnail)
        .onDisappear {
            #if canImport(AppKit)
            imageLoadTask?.cancel()
            #endif
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        #if canImport(AppKit)
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if loadFailed {
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Missing File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if item.kind == .video {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
        #else
        if loadFailed {
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Missing File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: item.kind == .video ? "play.rectangle.fill" : "photo")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        }
        #endif
    }

    private func loadThumbnail() {
        #if canImport(AppKit)
        guard item.kind == .image, image == nil else { return }
        imageLoadTask?.cancel()
        loadFailed = false
        let url = MediaManager.resolvedURL(for: item.fileName)
        imageLoadTask = Task { @MainActor in
            let cgImage = await EditorImageFileLoader.thumbnail(from: url)
            guard !Task.isCancelled else { return }
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else {
                loadFailed = true
            }
        }
        #else
        loadFailed = true // Simulate failure on non-AppKit for missing ImageFileLoader
        #endif
    }
}

#if canImport(AppKit)
private enum EditorImageFileLoader {
    /// Editor attachment tiles are small; 600px covers them at Retina without
    /// decoding the full-resolution file.
    static func thumbnail(from url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
            ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }.value
    }
}
#endif
