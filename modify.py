import re

with open('/Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift', 'r') as f:
    content = f.read()

# 1. State vars
content = content.replace(
    '@State private var isCollectionsSectionExpanded: Bool = false',
    '@State private var isAllSnippetsExpanded: Bool = false\n    @State private var expandedCollections: Set<PersistentIdentifier> = []'
)

# 2. ModernSidebar init
content = content.replace(
    'isCollectionsSectionExpanded: $isCollectionsSectionExpanded,',
    'isAllSnippetsExpanded: $isAllSnippetsExpanded,\n            expandedCollections: $expandedCollections,'
)

content = content.replace(
    'onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) }',
    'onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },\n            onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) },\n            onHandleDrop: { items, collection in handleDrop(items: items, to: collection) }'
)

# 3. Remove collectionsSection from legacySidebar
content = re.sub(r'\s*collectionsSection\s+', '\n', content)

# 4. Modify librarySection
new_library_section = '''    private var librarySection: some View {
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
                        handleDrop(items: items, to: nil)
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
                                handleDrop(items: items, to: collection)
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
    }'''

content = re.sub(r'    private var librarySection: some View \{.*?(?=\n    private var collectionsSection: some View \{)', new_library_section + '\n', content, flags=re.DOTALL)

# 5. Remove collectionsSection
content = re.sub(r'    private var collectionsSection: some View \{.*?(?=\n    private var recentSection: some View \{)', '', content, flags=re.DOTALL)

# 6. Remove ▸ from sidebarRow and recentRow
content = re.sub(r'\s*Text\(isActive \? "▸" : " "\)\n\s*\.font\(Mono\.font\(size: 11, weight: \.bold\)\)\n\s*\.foregroundStyle\(isActive \? accent : theme\.textFaint\)\n\s*\.frame\(width: 10, alignment: \.leading\)', '', content)

# 7. Add snippetContextMenu, sidebarSnippetRow, handleDrop, copySnippet
helpers = '''    @ViewBuilder
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
        let isActive = selectedSnippetID == snippet.persistentModelID
        Button {
            selectedSnippetID = snippet.persistentModelID
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

    private func copySnippet(_ snippet: Snippet, to collection: Collection) {
        if !snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID }) {
            snippet.collections.append(collection)
            collection.updatedAt = .now
            snippet.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func handleDrop(items: [String], to collection: Collection?) -> Bool {
        guard let first = items.first, let hash = Int(first) else { return false }
        guard let snippet = snippets.first(where: { $0.persistentModelID.hashValue == hash }) else { return false }
        
        if let collection {
            moveSnippet(snippet, to: collection)
        } else {
            moveSnippetToLibrary(snippet)
        }
        return true
    }'''

content = content.replace('    private func delete(_ collection: Collection) {', helpers + '\n\n    private func delete(_ collection: Collection) {')

# 8. Update recentRow context menu
content = re.sub(r'\.contextMenu \{\n\s*Button \{ editingSnippet.*?\}\n\s*\}', r'.contextMenu {\n            snippetContextMenu(for: snippet)\n        }', content, flags=re.DOTALL)

# 9. ModernSidebar updates
content = content.replace('@Binding var isCollectionsSectionExpanded: Bool', '@Binding var isAllSnippetsExpanded: Bool\n    @Binding var expandedCollections: Set<PersistentIdentifier>')
content = content.replace('let onMoveSnippetToCollection: (Snippet, Collection) -> Void', 'let onMoveSnippetToCollection: (Snippet, Collection) -> Void\n    let onCopySnippetToCollection: (Snippet, Collection) -> Void\n    let onHandleDrop: ([String], Collection?) -> Bool')

modern_sidebar_snippets = '''            Section("Snippets", isExpanded: $isLibrarySectionExpanded) {
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
                .dropDestination(for: String.self) { items, _ in onHandleDrop(items, nil) }

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
                    .dropDestination(for: String.self) { items, _ in onHandleDrop(items, collection) }
                }
            }'''

content = re.sub(r'            Section\("Snippets".*?(?=\n\n            if !recentSnippets\.isEmpty)', modern_sidebar_snippets, content, flags=re.DOTALL)

# Remove the standalone Collections section
content = re.sub(r'\n            Section\("Collections", isExpanded: \$isCollectionsSectionExpanded\) \{.*?(?=\n\n            if !availableLanguages\.isEmpty)', '', content, flags=re.DOTALL)

with open('/Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift', 'w') as f:
    f.write(content)
