import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var snippets: [Snippet]
    @Query(sort: [SortDescriptor(\SnippetCollection.updatedAt, order: .reverse)])
    private var collections: [SnippetCollection]

    @State private var selectedLanguage: SupportedLanguage? = nil
    @State private var searchText: String = ""
    @State private var editingSnippet: Snippet? = nil
    @State private var isPresentingNew: Bool = false
    @State private var isPresentingCollectionEditor: Bool = false
    @State private var editingCollection: SnippetCollection? = nil
    @State private var collectionDraftName: String = ""
    @State private var collectionDraftSnippetIDs: Set<PersistentIdentifier> = []
    @State private var selectedSnippetID: PersistentIdentifier? = nil
    enum SidebarSelectionContext: Equatable {
        case recent
        case library
    }
    @State private var sidebarSelectionContext: SidebarSelectionContext? = nil
    @State private var selectedCollectionID: PersistentIdentifier? = nil
    @State private var sidebarSearch: String = ""
    @State private var isLibrarySectionExpanded: Bool = true
    @State private var isRecentSectionExpanded: Bool = true
    @State private var isLanguagesSectionExpanded: Bool = true
    @State private var isAllSnippetsExpanded: Bool = false
    @State private var expandedCollections: Set<PersistentIdentifier> = []

    private var collectionNameMatches: [SnippetCollection] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return collections.filter { $0.name.lowercased().contains(needle) }
    }

    private var baseFilteredSnippets: [Snippet] {
        snippets.filter { snippet in
            if let selectedLanguage, snippet.language != selectedLanguage.rawValue { return false }
            if let selectedCollectionID {
                return snippet.collections.contains(where: { $0.persistentModelID == selectedCollectionID })
            }
            return true
        }
    }

    private var snippetsInCollectionSearchSection: [Snippet] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let matchedIDs = Set(collectionNameMatches.map(\.persistentModelID))
        return baseFilteredSnippets.filter { snippet in
            snippet.collections.contains(where: { matchedIDs.contains($0.persistentModelID) })
        }
    }

    private var snippetsInContentSearchSection: [Snippet] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let needle = searchText.lowercased()
        let alreadyIncluded = Set(snippetsInCollectionSearchSection.map(\.persistentModelID))
        return baseFilteredSnippets.filter { snippet in
            let containsText =
                snippet.title.lowercased().contains(needle) ||
                snippet.snippetDescription.lowercased().contains(needle) ||
                snippet.code.lowercased().contains(needle)
            return containsText && !alreadyIncluded.contains(snippet.persistentModelID)
        }
    }

    private var gallerySnippets: [Snippet] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? baseFilteredSnippets : []
    }

    private var availableLanguages: [SupportedLanguage] {
        let used = Set(snippets.compactMap { SupportedLanguage(rawValue: $0.language) })
        return SupportedLanguage.allCases.filter { used.contains($0) }
    }

    private var sidebarFilteredLanguages: [SupportedLanguage] {
        guard !sidebarSearch.isEmpty else { return availableLanguages }
        let needle = sidebarSearch.lowercased()
        return availableLanguages.filter { $0.rawValue.lowercased().contains(needle) }
    }

    private var recentSnippets: [Snippet] {
        Array(snippets.prefix(5))
    }

    private var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return snippets.first(where: { $0.persistentModelID == id })
    }

    private var selectedCollection: SnippetCollection? {
        guard let id = selectedCollectionID else { return nil }
        return collections.first(where: { $0.persistentModelID == id })
    }

    private var backgroundPalette: [Color] {
        var colors: [Color] = []
        var seenHex = Set<String>()

        for snippet in snippets {
            guard
                let language = SupportedLanguage(rawValue: snippet.language),
                !seenHex.contains(language.accentHex.lowercased())
            else { continue }

            seenHex.insert(language.accentHex.lowercased())
            colors.append(theme.accentColor(for: language))
        }
        return colors
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            ZStack {
                Group {
                    DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78)
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    SnippetGalleryView(
                        snippets: gallerySnippets,
                        collectionMatchSnippets: snippetsInCollectionSearchSection,
                        contentMatchSnippets: snippetsInContentSearchSection,
                        searchQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchText: $searchText,
                        selectedLanguage: $selectedLanguage,
                        availableLanguages: availableLanguages,
                        onSelect: { snippet in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSnippetID = snippet.persistentModelID
                                sidebarSelectionContext = .library
                            }
                        },
                        onNew: { isPresentingNew = true }
                    )
                    .blur(radius: selectedSnippet == nil ? 0 : 2)
                    .saturation(selectedSnippet == nil ? 1.0 : 0.95)
                    .allowsHitTesting(selectedSnippet == nil)

                    StatusBar(segments: detailStatusSegments())
                }

                if let snippet = selectedSnippet {
                    Color.black
                        .opacity(colorScheme == .dark ? 0.34 : 0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                selectedSnippetID = nil
                            }
                        }
                        .transition(.opacity)
                        .zIndex(1)

                    GeometryReader { proxy in
                        let cardWidth = min(max(proxy.size.width * 0.86, 700), 1080)
                        let cardHeight = min(max(proxy.size.height * 0.84, 500), 860)

                        SnippetDetailView(snippet: snippet) {
                            editingSnippet = snippet
                        } onDelete: {
                            delete(snippet)
                        } onClose: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                selectedSnippetID = nil
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(theme.borderStrong, lineWidth: 1)
                                }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.52 : 0.24), radius: 30, x: 0, y: 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                                removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                            )
                        )
                    }
                    .zIndex(2)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: selectedSnippetID)
        }
        .sheet(isPresented: $isPresentingNew) {
            SnippetEditorView(mode: .create, availableCollections: collections) { newSnippet in
                modelContext.insert(newSnippet)
                try modelContext.save()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    selectedSnippetID = newSnippet.persistentModelID
                    sidebarSelectionContext = .library
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(mode: .edit(snippet), availableCollections: collections) { _ in
                try modelContext.save()
            }
        }
        .sheet(isPresented: $isPresentingCollectionEditor) {
            CollectionEditorSheet(
                title: editingCollection == nil ? "New collection" : "Edit collection",
                collectionName: $collectionDraftName,
                selectedSnippetIDs: $collectionDraftSnippetIDs,
                snippets: snippets,
                onCancel: { isPresentingCollectionEditor = false },
                onSave: { commitCollectionEditor() }
            )
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }

    private func detailStatusSegments() -> [StatusBar.Segment] {
        var segs: [StatusBar.Segment] = []
        segs.append(.init(icon: "terminal", label: "snippets"))
        if let snippet = selectedSnippet {
            let lang = SupportedLanguage(rawValue: snippet.language) ?? .unknown
            let lines = snippet.code.split(separator: "\n").count
            segs.append(.init(label: "ln \(max(lines, 1))"))
            segs.append(.init(label: lang.rawValue.lowercased(), tint: Color(hex: lang.accentHex)))
            if !snippet.mediaItems.isEmpty {
                segs.append(.init(icon: "paperclip", label: "\(snippet.mediaItems.count)"))
            }
        } else {
            segs.append(.init(label: "\(baseFilteredSnippets.count) / \(snippets.count) snippets"))
            if let lang = selectedLanguage {
                segs.append(.init(label: "filter: \(lang.rawValue.lowercased())", tint: Color(hex: lang.accentHex)))
            }
            if let selectedCollection {
                segs.append(.init(label: "collection: \(selectedCollection.name.lowercased())", tint: theme.accent))
            }
        }
        segs.append(.init(label: "utf-8"))
        return segs
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 26.0, *) {
            modernSidebar
        } else {
            legacySidebar
        }
    }

    // MARK: - Modern (Tahoe / macOS 26+) sidebar

    @available(macOS 26.0, *)
    private var modernSidebar: some View {
        ModernSidebar(
            snippets: snippets,
            collections: collections,
            recentSnippets: recentSnippets,
            availableLanguages: availableLanguages,
            sidebarFilteredLanguages: sidebarFilteredLanguages,
            sidebarSearch: $sidebarSearch,
            selectedLanguage: $selectedLanguage,
            selectedSnippetID: $selectedSnippetID,
            sidebarSelectionContext: $sidebarSelectionContext,
            selectedCollectionID: $selectedCollectionID,
            isLibrarySectionExpanded: $isLibrarySectionExpanded,
            isRecentSectionExpanded: $isRecentSectionExpanded,
            isLanguagesSectionExpanded: $isLanguagesSectionExpanded,
            isAllSnippetsExpanded: $isAllSnippetsExpanded,
            expandedCollections: $expandedCollections,
            onNew: { beginCreateCollection() },
            onEditCollection: { collection in beginEditCollection(collection) },
            onDeleteCollection: { collection in delete(collection) },
            onEditSnippet: { snippet in editingSnippet = snippet },
            onDeleteSnippet: { snippet in delete(snippet) },
            onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
            onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
            onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) },
            onHandleDrop: { items, collection in handleDrop(items: items, to: collection) }
        )
    }

    // MARK: - Legacy (pre-Tahoe) sidebar

    private var legacySidebar: some View {
        ZStack {
            theme.canvasDeep.ignoresSafeArea()
            DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.72)
                .opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sidebarSearchBar
                    .padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        newSnippetButton

                        librarySection

                        if !recentSnippets.isEmpty {
                            recentSection
                        }
if !availableLanguages.isEmpty {
                            languagesSection
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)

                sidebarFooter
            }
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(Mono.font(size: 11, weight: .bold))
                .foregroundStyle(theme.textFaint)
            TextField("filter languages…", text: $sidebarSearch)
                .textFieldStyle(.plain)
                .font(Mono.font(size: 11))
                .foregroundStyle(theme.text)
            if !sidebarSearch.isEmpty {
                Button {
                    sidebarSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.surface.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
        .padding(.horizontal, 14)
    }

    private var newSnippetButton: some View {
        Button {
            beginCreateCollection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(Mono.font(size: 12, weight: .bold))
                Text("new collection")
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text("⌘")
                    Text("⇧N")
                }
                .font(Mono.font(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.14))
                }
            }
            .font(Mono.font(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(theme.accent)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    private var librarySection: some View {
        DisclosureGroup(isExpanded: $isLibrarySectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snippets) { snippet in
                            sidebarSnippetRow(for: snippet)
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    sidebarRow(
                        icon: "square.grid.2x2",
                        title: "all snippets",
                        count: snippets.count,
                        isActive: selectedLanguage == nil && selectedSnippetID == nil && selectedCollectionID == nil,
                        accent: theme.accent
                    ) {
                        selectedLanguage = nil
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                    }
                    .dropDestination(for: String.self) { items, _ in
                        return handleDrop(items: items, to: nil)
                    }
                }

                ForEach(collections) { collection in
                    let isExpanded = Binding(
                        get: { expandedCollections.contains(collection.persistentModelID) },
                        set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
                    )
                    DisclosureGroup(isExpanded: isExpanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(collection.snippets) { snippet in
                                sidebarSnippetRow(for: snippet)
                            }
                        }
                        .padding(.leading, 12)
                    } label: {
                        collectionRow(for: collection)
                            .dropDestination(for: String.self) { items, _ in
                                return handleDrop(items: items, to: collection)
                            }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("snippets")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }


    private var recentSection: some View {
        DisclosureGroup(isExpanded: $isRecentSectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recentSnippets) { snippet in
                    recentRow(for: snippet)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("recent")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }

    private var languagesSection: some View {
        DisclosureGroup(isExpanded: $isLanguagesSectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("languages")
                        .font(Mono.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    Text("\(sidebarFilteredLanguages.count)")
                        .font(Mono.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textFaint)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

                ForEach(sidebarFilteredLanguages) { language in
                    sidebarRow(
                        icon: language.symbolName,
                        title: language.rawValue.lowercased(),
                        count: snippets.filter { $0.language == language.rawValue }.count,
                        isActive: selectedLanguage == language && selectedSnippetID == nil,
                        accent: Color(hex: language.accentHex) ?? theme.accent
                    ) {
                        selectedLanguage = (selectedLanguage == language) ? nil : language
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                    }
                }
                if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
                    Text("no matches")
                        .font(Mono.font(size: 11))
                        .foregroundStyle(theme.textFaint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text("languages")
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Text("\(sidebarFilteredLanguages.count)")
                    .font(Mono.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textFaint)
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(
        icon: String,
        title: String,
        count: Int,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(accent)
                Text(title)
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func recentRow(for snippet: Snippet) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .recent
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .recent
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            snippetContextMenu(for: snippet)
        }
    }

    @ViewBuilder
    private func collectionRow(for collection: SnippetCollection) -> some View {
        sidebarRow(
            icon: "folder",
            title: collection.name.lowercased(),
            count: collection.snippets.count,
            isActive: selectedCollectionID == collection.persistentModelID && selectedSnippetID == nil,
            accent: theme.accent
        ) {
            selectedCollectionID = (selectedCollectionID == collection.persistentModelID) ? nil : collection.persistentModelID
            selectedSnippetID = nil
        }
        .contextMenu {
            Button { beginEditCollection(collection) } label: {
                Label("Edit collection", systemImage: "pencil")
            }
            Button(role: .destructive) { delete(collection) } label: {
                Label("Delete collection", systemImage: "trash")
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            footerStat(icon: "doc.text", value: "\(snippets.count)", label: "snips")
            footerStat(icon: "chevron.left.forwardslash.chevron.right", value: "\(availableLanguages.count)", label: "langs")
            Spacer()
            if let last = snippets.first {
                Text(last.updatedAt, format: .relative(presentation: .numeric))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(theme.surfaceElevated.opacity(0.5))
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
        }
    }

    private func footerStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Mono.font(size: 9, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Text(value)
                .font(Mono.font(size: 11, weight: .bold))
                .foregroundStyle(theme.text)
            Text(label)
                .font(Mono.font(size: 10))
                .foregroundStyle(theme.textFaint)
        }
    }

    private func delete(_ snippet: Snippet) {
        if selectedSnippetID == snippet.persistentModelID {
            selectedSnippetID = nil
        }
        for item in snippet.mediaItems {
            MediaManager.deleteFile(for: item)
        }
        modelContext.delete(snippet)
        try? modelContext.save()
    }

    private func beginCreateCollection() {
        editingCollection = nil
        collectionDraftName = ""
        collectionDraftSnippetIDs = []
        isPresentingCollectionEditor = true
    }

    private func beginEditCollection(_ collection: SnippetCollection) {
        editingCollection = collection
        collectionDraftName = collection.name
        collectionDraftSnippetIDs = Set(collection.snippets.map(\.persistentModelID))
        isPresentingCollectionEditor = true
    }

    private func commitCollectionEditor() {
        let trimmed = collectionDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            collectionDraftName = ""
            collectionDraftSnippetIDs = []
            isPresentingCollectionEditor = false
        }
        guard !trimmed.isEmpty else { return }
        let collection: SnippetCollection
        if let editingCollection {
            collection = editingCollection
            collection.name = trimmed
        } else if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            collection = existing
        } else {
            collection = SnippetCollection(name: trimmed)
            modelContext.insert(collection)
        }

        let selectedIDs = collectionDraftSnippetIDs
        for snippet in snippets {
            let shouldBeInCollection = selectedIDs.contains(snippet.persistentModelID)
            let isAlreadyInCollection = snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID })
            if shouldBeInCollection && !isAlreadyInCollection {
                snippet.collections.append(collection)
            } else if !shouldBeInCollection && isAlreadyInCollection {
                snippet.collections.removeAll(where: { $0.persistentModelID == collection.persistentModelID })
            }
            if snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID }) {
                snippet.updatedAt = .now
            }
        }
        collection.snippets = snippets.filter { selectedIDs.contains($0.persistentModelID) }
        collection.updatedAt = .now
        try? modelContext.save()
        selectedCollectionID = collection.persistentModelID
        isLibrarySectionExpanded = true
        expandedCollections.insert(collection.persistentModelID)
    }

    @ViewBuilder
    private func snippetContextMenu(for snippet: Snippet) -> some View {
        Button { editingSnippet = snippet } label: {
            Label("Edit snippet", systemImage: "pencil")
        }
        Button(role: .destructive) { delete(snippet) } label: {
            Label("Delete snippet", systemImage: "trash")
        }
        Menu("Move to") {
            Button { moveSnippetToLibrary(snippet) } label: {
                Label("All snippets", systemImage: "square.grid.2x2")
            }
            ForEach(collections) { collection in
                Button { moveSnippet(snippet, to: collection) } label: {
                    Label(collection.name, systemImage: "folder")
                }
            }
        }
        Menu("Copy to") {
            ForEach(collections) { collection in
                Button { copySnippet(snippet, to: collection) } label: {
                    Label(collection.name, systemImage: "folder")
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSnippetRow(for snippet: Snippet) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .library
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .library
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
            snippetContextMenu(for: snippet)
        }
    }

    private func copySnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        if !snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID }) {
            snippet.collections.append(collection)
            collection.updatedAt = .now
            snippet.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func handleDrop(items: [String], to collection: SnippetCollection?) -> Bool {
        guard let first = items.first, let hash = Int(first) else { return false }
        guard let snippet = snippets.first(where: { $0.persistentModelID.hashValue == hash }) else { return false }
        
        if let collection {
            moveSnippet(snippet, to: collection)
        } else {
            moveSnippetToLibrary(snippet)
        }
        return true
    }

    private func delete(_ collection: SnippetCollection) {
        for snippet in snippets {
            snippet.collections.removeAll(where: { $0.persistentModelID == collection.persistentModelID })
        }
        if selectedCollectionID == collection.persistentModelID {
            selectedCollectionID = nil
        }
        modelContext.delete(collection)
        try? modelContext.save()
    }

    private func moveSnippetToLibrary(_ snippet: Snippet) {
        for collection in collections {
            collection.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
            collection.updatedAt = .now
        }
        snippet.collections = []
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func moveSnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        for other in collections {
            other.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
        }
        snippet.collections = [collection]
        if !collection.snippets.contains(where: { $0.persistentModelID == snippet.persistentModelID }) {
            collection.snippets.append(snippet)
        }
        collection.updatedAt = .now
        snippet.updatedAt = .now
        try? modelContext.save()
    }
}

// MARK: - Modern sidebar (native SwiftUI + Liquid Glass on macOS 26+)

@available(macOS 26.0, *)
private struct ModernSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Selection: Hashable {
        case all
        case language(String)
        case collection(PersistentIdentifier)
        case snippet(PersistentIdentifier)
        case recentSnippet(PersistentIdentifier)
    }

    let snippets: [Snippet]
    let collections: [SnippetCollection]
    let recentSnippets: [Snippet]
    let availableLanguages: [SupportedLanguage]
    let sidebarFilteredLanguages: [SupportedLanguage]

    @Binding var sidebarSearch: String
    @Binding var selectedLanguage: SupportedLanguage?
    @Binding var selectedSnippetID: PersistentIdentifier?
    @Binding var sidebarSelectionContext: ContentView.SidebarSelectionContext?
    @Binding var selectedCollectionID: PersistentIdentifier?
    @Binding var isLibrarySectionExpanded: Bool
    @Binding var isRecentSectionExpanded: Bool
    @Binding var isLanguagesSectionExpanded: Bool
    @Binding var isAllSnippetsExpanded: Bool
    @Binding var expandedCollections: Set<PersistentIdentifier>

    let onNew: () -> Void
    let onEditCollection: (SnippetCollection) -> Void
    let onDeleteCollection: (SnippetCollection) -> Void
    let onEditSnippet: (Snippet) -> Void
    let onDeleteSnippet: (Snippet) -> Void
    let onMoveSnippetToLibrary: (Snippet) -> Void
    let onMoveSnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onCopySnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onHandleDrop: ([String], SnippetCollection?) -> Bool

    private var theme: Theme { Theme.current(colorScheme) }

    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if let id = selectedSnippetID {
                    return sidebarSelectionContext == .recent ? .recentSnippet(id) : .snippet(id)
                }
                if let id = selectedCollectionID { return .collection(id) }
                if let lang = selectedLanguage { return .language(lang.rawValue) }
                return .all
            },
            set: { newValue in
                switch newValue {
                case .all, .none:
                    selectedLanguage = nil
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .language(let raw):
                    selectedLanguage = SupportedLanguage(rawValue: raw)
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .collection(let id):
                    selectedCollectionID = id
                    selectedLanguage = nil
                    selectedSnippetID = nil
                case .snippet(let id):
                    selectedSnippetID = id
                    sidebarSelectionContext = .library
                case .recentSnippet(let id):
                    selectedSnippetID = id
                    sidebarSelectionContext = .recent
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Snippets", isExpanded: $isLibrarySectionExpanded) {
                DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                    ForEach(snippets) { snippet in
                        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                        }
                        .tag(Selection.snippet(snippet.persistentModelID))
                        .draggable(String(snippet.persistentModelID.hashValue))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                            Menu("Move to") {
                                Button { onMoveSnippetToLibrary(snippet) } label: { Label("All snippets", systemImage: "square.grid.2x2") }
                                ForEach(collections) { collection in
                                    Button { onMoveSnippetToCollection(snippet, collection) } label: { Label(collection.name, systemImage: "folder") }
                                }
                            }
                            Menu("Copy to") {
                                ForEach(collections) { collection in
                                    Button { onCopySnippetToCollection(snippet, collection) } label: { Label(collection.name, systemImage: "folder") }
                                }
                            }
                        }
                    }
                } label: {
                    Label {
                        HStack {
                            Text("All snippets")
                            Spacer()
                            Text("\(snippets.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                .tag(Selection.all)
                .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }

                ForEach(collections) { collection in
                    let isExpanded = Binding(
                        get: { expandedCollections.contains(collection.persistentModelID) },
                        set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
                    )
                    DisclosureGroup(isExpanded: isExpanded) {
                        ForEach(collection.snippets) { snippet in
                            let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                            let accent = Color(hex: language.accentHex) ?? .accentColor
                            Label {
                                Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } icon: {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 8, height: 8)
                            }
                            .tag(Selection.snippet(snippet.persistentModelID))
                            .draggable(String(snippet.persistentModelID.hashValue))
                            .contextMenu {
                                Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                                Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                                Menu("Move to") {
                                    Button { onMoveSnippetToLibrary(snippet) } label: { Label("All snippets", systemImage: "square.grid.2x2") }
                                    ForEach(collections) { target in
                                        Button { onMoveSnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: "folder") }
                                    }
                                }
                                Menu("Copy to") {
                                    ForEach(collections) { target in
                                        Button { onCopySnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: "folder") }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(collection.name)
                                Spacer()
                                Text("\(collection.snippets.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "folder")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .tag(Selection.collection(collection.persistentModelID))
                    .contextMenu {
                        Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                        Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                    }
                    .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, collection) }
                }
            }

            if !recentSnippets.isEmpty {
                Section("Recent", isExpanded: $isRecentSectionExpanded) {
                    ForEach(recentSnippets) { snippet in
                        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                        }
                        .tag(Selection.recentSnippet(snippet.persistentModelID))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: {
                                Label("Edit snippet", systemImage: "pencil")
                            }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: {
                                Label("Delete snippet", systemImage: "trash")
                            }
                            Menu("Move to") {
                                Button { onMoveSnippetToLibrary(snippet) } label: {
                                    Label("Snippets", systemImage: "square.grid.2x2")
                                }
                                ForEach(collections) { collection in
                                    Button { onMoveSnippetToCollection(snippet, collection) } label: {
                                        Label(collection.name, systemImage: "folder")
                                    }
                                }
                            }
                        }
                    }
                }
            }


            if !availableLanguages.isEmpty {
                Section("Languages", isExpanded: $isLanguagesSectionExpanded) {
                    ForEach(sidebarFilteredLanguages) { language in
                        let count = snippets.filter { $0.language == language.rawValue }.count
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        Label {
                            HStack {
                                Text(language.rawValue)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: language.symbolName)
                                .foregroundStyle(accent)
                        }
                        .tag(Selection.language(language.rawValue))
                    }

                    if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(
            text: $sidebarSearch,
            placement: .sidebar,
            prompt: Text("Filter languages")
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onNew) {
                Label("New Collection", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .controlSize(.large)
            .clipShape(Capsule(style: .continuous))
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .padding(12)
        }
    }
}

private struct CollectionEditorSheet: View {
    let title: String
    @Binding var collectionName: String
    @Binding var selectedSnippetIDs: Set<PersistentIdentifier>
    let snippets: [Snippet]
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Collection name", text: $collectionName)
                    .textFieldStyle(.roundedBorder)
                Text("Add existing snippets (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(snippets) { snippet in
                            Button {
                                if selectedSnippetIDs.contains(snippet.persistentModelID) {
                                    selectedSnippetIDs.remove(snippet.persistentModelID)
                                } else {
                                    selectedSnippetIDs.insert(snippet.persistentModelID)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedSnippetIDs.contains(snippet.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}
