require 'fileutils'

# Read properties from current ModernSidebar.swift
modern = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")
body_start = modern.index("    var body: some View {")

# Extract properties up to `var body`
properties = modern[0...body_start]

# We also need the `theme` property.
theme_prop = <<-SWIFT
    private var theme: Theme { Theme.current(colorScheme) }

    private var backgroundPalette: [Color] {
        var colors: [Color] = []
        var seenHex = Set<String>()
        for snippet in snippets {
            guard let language = SupportedLanguage(rawValue: snippet.language),
                  !seenHex.contains(language.accentHex.lowercased()) else { continue }
            seenHex.insert(language.accentHex.lowercased())
            colors.append(theme.accentColor(for: language))
        }
        return colors
    }

SWIFT

# Construct the body with ZStack, liquid glass button, etc.
body = <<-SWIFT
    var body: some View {
        ZStack {
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

                        if !frequentlyUsedSnippets.isEmpty {
                            frequentlyUsedSection
                        }
                        if !availableLanguages.isEmpty {
                            languagesSection
                        }

                        sidebarRow(
                            icon: "trash",
                            title: "trash",
                            count: trashedItemCount,
                            isActive: sidebarSelectionContext == .trash,
                            accent: .red
                        ) {
                            sidebarSelectionContext = .trash
                            selectedSnippetID = nil
                            selectedCollectionID = nil
                            selectedLanguages.removeAll()
                            selectedSearchCollections.removeAll()
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(Mono.font(size: 11, weight: .bold))
                .foregroundStyle(theme.textFaint)
            TextField("filter...", text: $sidebarSearch)
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
        Button(action: onNew) {
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
            .liquidGlassSurface(
                in: Capsule(style: .continuous),
                tint: theme.accent,
                interactive: true,
                borderOpacity: colorScheme == .dark ? 0.22 : 0.40,
                shadowRadius: 0,
                shadowY: 0
            )
            .overlay {
                if colorScheme == .light {
                    Capsule(style: .continuous)
                        .fill(theme.accent.opacity(0.15))
                        .allowsHitTesting(false)
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
                            sidebarSnippetRow(for: snippet, context: .allSnippets)
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    sidebarRow(
                        icon: "square.grid.2x2",
                        title: "all snippets",
                        count: snippets.count,
                        isActive: selectedLanguages.isEmpty && selectedSnippetID == nil && selectedCollectionID == nil && sidebarSelectionContext != .trash,
                        accent: theme.accent
                    ) {
                        selectedLanguages.removeAll()
                        selectedSearchCollections.removeAll()
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                        sidebarSelectionContext = .allSnippets
                    }
                    .dropDestination(for: String.self) { items, _ in
                        return onHandleDrop(items, nil)
                    }
                }

                ForEach(topLevelCollections) { collection in
                    legacyCollectionTree(for: collection)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("snippets")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }

    private var frequentlyUsedSection: some View {
        DisclosureGroup(isExpanded: $isFrequentlyUsedSectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(frequentlyUsedSnippets) { snippet in
                    frequentlyUsedRow(for: snippet)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("frequently used")
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
                    Text("\\(sidebarFilteredLanguages.count)")
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
                        isActive: selectedLanguages.contains(language),
                        accent: Color(hex: language.accentHex) ?? theme.accent
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedSearchCollections.removeAll()
                            selectedSnippetID = nil
                            selectedCollectionID = nil
                            sidebarSelectionContext = nil
                            if selectedLanguages.contains(language) {
                                selectedLanguages.remove(language)
                                if selectedLanguages.isEmpty {
                                    sidebarSelectionContext = .allSnippets
                                }
                            } else {
                                selectedLanguages.insert(language)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("languages")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }

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
                Text("\\(count)")
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
    private func frequentlyUsedRow(for snippet: Snippet) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .frequentlyUsed
        Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = .frequentlyUsed
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarSnippetRow(for snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        
        Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = context
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legacyCollectionTree(for collection: SnippetCollection, level: Int = 0) -> some View {
        let isActive = selectedCollectionID == collection.persistentModelID && selectedSnippetID == nil
        let accent: Color = collection.colorHex.isEmpty ? theme.accent : (Color(hex: collection.colorHex) ?? theme.accent)
        let hasChildren = !collection.children.filter { !$0.isDeleted }.isEmpty
        let hasSnippets = !collection.snippets.filter { $0.deletedAt == nil }.isEmpty
        let isExpandedBinding = Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { isExpanded in
                if isExpanded {
                    expandedCollections.insert(collection.persistentModelID)
                } else {
                    expandedCollections.remove(collection.persistentModelID)
                }
            }
        )

        VStack(alignment: .leading, spacing: 2) {
            if hasChildren || hasSnippets {
                DisclosureGroup(isExpanded: isExpandedBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(collection.children.filter { !$0.isDeleted }.sorted(by: { $0.updatedAt > $1.updatedAt })) { child in
                            legacyCollectionTree(for: child, level: level + 1)
                        }
                        ForEach(collection.snippets.filter { $0.deletedAt == nil }.sorted(by: { $0.updatedAt > $1.updatedAt })) { snippet in
                            sidebarSnippetRow(for: snippet, context: .collection(collection.persistentModelID))
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    sidebarRow(
                        icon: collection.displayIconName,
                        title: collection.name.lowercased(),
                        count: collection.snippets.filter { $0.deletedAt == nil }.count,
                        isActive: isActive,
                        accent: accent
                    ) {
                        selectedCollectionID = collection.persistentModelID
                        selectedSearchCollections.removeAll()
                        selectedSnippetID = nil
                        sidebarSelectionContext = .collection(collection.persistentModelID)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        return onHandleDrop(items, collection)
                    }
                    .contextMenu {
                        Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                        Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                    }
                }
            } else {
                sidebarRow(
                    icon: collection.displayIconName,
                    title: collection.name.lowercased(),
                    count: 0,
                    isActive: isActive,
                    accent: accent
                ) {
                    selectedCollectionID = collection.persistentModelID
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    sidebarSelectionContext = .collection(collection.persistentModelID)
                }
                .dropDestination(for: String.self) { items, _ in
                    return onHandleDrop(items, collection)
                }
                .contextMenu {
                    Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                }
            }
        }
    }
}
SWIFT

File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", properties + theme_prop + body)
