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

                        if !frequentlyUsedSnippets.isEmpty {
                            frequentlyUsedSection
                        }
                        if !availableLanguages.isEmpty {
                            languagesSection
                        }

                        sidebarRow(
                            icon: "trash",
                            title: "trash",
                            count: trashedSnippetCount,
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
                        return handleDrop(items: items, to: nil)
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
                        isActive: selectedLanguages.contains(language) && selectedSnippetID == nil,
                        accent: Color(hex: language.accentHex) ?? theme.accent
                    ) {
                        if selectedLanguages.contains(language) {
                            selectedLanguages.remove(language)
                        } else {
                            selectedLanguages.insert(language)
                        }
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                        sidebarSelectionContext = .allSnippets
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
    private func frequentlyUsedRow(for snippet: Snippet) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .frequentlyUsed
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .frequentlyUsed
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
        let accent = collection.displayColor
        let isActive = selectedCollectionID == collection.persistentModelID && selectedSnippetID == nil && sidebarSelectionContext == .collection(collection.persistentModelID)
        Button {
            if selectedCollectionID == collection.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID) {
                selectedCollectionID = nil
                sidebarSelectionContext = .allSnippets
            } else {
                selectedCollectionID = collection.persistentModelID
                sidebarSelectionContext = .collection(collection.persistentModelID)
            }
            selectedSearchCollections.removeAll()
            selectedLanguages.removeAll()
            selectedSnippetID = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collection.displayIconName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(accent)
                
                Text(collection.name.lowercased())
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
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
        .contextMenu {
            Button { beginEditCollection(collection) } label: {
                Label("Edit collection", systemImage: "pencil")
            }
            Button(role: .destructive) { delete(collection) } label: {
                Label("Delete collection", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func legacyCollectionTree(for collection: SnippetCollection) -> some View {
        let isExpanded = Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
        )
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(collection.children) { child in
                    AnyView(legacyCollectionTree(for: child))
                }
                ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
                    sidebarSnippetRow(for: snippet, context: .collection(collection.persistentModelID))
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
        lastDeletedSnippet = DeletedSnippetSnapshot(
            id: snippet.persistentModelID,
            title: snippet.title,
            snippetDescription: snippet.snippetDescription,
            language: snippet.language,
            code: snippet.code,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt,
            copyCount: snippet.copyCount,
            mediaItems: snippet.mediaItems.map { item in
                DeletedMediaSnapshot(fileName: item.fileName, kind: item.kind, addedAt: item.addedAt)
            },
            collectionIDs: snippet.collections.map(\.persistentModelID)
        )

        if selectedSnippetID == snippet.persistentModelID {
            selectedSnippetID = nil
        }
        // Soft-delete: set deletedAt so the snippet is retained in Trash for 30 days
        snippet.deletedAt = Date.now
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func restoreLastDeletedSnippet() -> PersistentIdentifier? {
        guard let snapshot = lastDeletedSnippet else { return nil }

        // Try to find the existing (soft-deleted) snippet and clear its deletedAt
        if let existing = allSnippets.first(where: { $0.persistentModelID == snapshot.id }) {
            existing.deletedAt = nil
            existing.updatedAt = .now
            try? modelContext.save()
            lastDeletedSnippet = nil
            return existing.persistentModelID
        }

        // Fallback: recreate from snapshot if the original object isn't available
        let restoredMedia = snapshot.mediaItems.map { media in
            MediaItem(fileName: media.fileName, kind: media.kind, addedAt: media.addedAt)
        }
        let restoredSnippet = Snippet(
            title: snapshot.title,
            snippetDescription: snapshot.snippetDescription,
            language: snapshot.language,
            code: snapshot.code,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            copyCount: snapshot.copyCount,
            mediaItems: restoredMedia,
            collections: collections.filter { snapshot.collectionIDs.contains($0.persistentModelID) }
        )

        modelContext.insert(restoredSnippet)
        try? modelContext.save()
        lastDeletedSnippet = nil
        return restoredSnippet.persistentModelID
    }

    private func performTrashCleanup() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
        for snippet in allSnippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                for media in snippet.mediaItems {
                    MediaManager.deleteFile(for: media)
                }
                modelContext.delete(snippet)
            }
        }
        try? modelContext.save()
    }

    private func beginCreateCollection() {
        editingCollection = nil
        collectionDraftName = ""
        collectionDraftColor = Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftIconName = SnippetCollection.defaultIconName
        collectionDraftSnippetIDs = []
        collectionDraftParentID = nil
        isSubcollectionDraft = false
        isPresentingCollectionEditor = true
    }

    private func beginEditCollection(_ collection: SnippetCollection) {
        editingCollection = collection
        collectionDraftName = collection.name
        collectionDraftColor = collection.displayColor
        collectionDraftIconName = collection.displayIconName
        collectionDraftSnippetIDs = Set(collection.snippets.map(\.persistentModelID))
        collectionDraftParentID = collection.parent?.persistentModelID
        isSubcollectionDraft = collection.parent != nil
        isPresentingCollectionEditor = true
    }

    private func resetCollectionDraft() {
        collectionDraftName = ""
        collectionDraftColor = Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftIconName = SnippetCollection.defaultIconName
        collectionDraftSnippetIDs = []
        collectionDraftParentID = nil
        isSubcollectionDraft = false
    }

    private func commitCollectionEditor() {
        let trimmed = collectionDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            resetCollectionDraft()
            isPresentingCollectionEditor = false
        }
        guard !trimmed.isEmpty else { return }
        let colorHex = collectionDraftColor.hexString(fallback: SnippetCollection.defaultColorHex)
        let iconName = SnippetCollection.validSFSymbolName(collectionDraftIconName)
        let collection: SnippetCollection
        if let editingCollection {
            collection = editingCollection
            collection.name = trimmed
        } else if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.parent?.persistentModelID == collectionDraftParentID }) {
            collection = existing
        } else {
            collection = SnippetCollection(name: trimmed, colorHex: colorHex, iconName: iconName)
            modelContext.insert(collection)
        }

        if isSubcollectionDraft, let parentID = collectionDraftParentID, let newParent = collections.first(where: { $0.persistentModelID == parentID }) {
            collection.parent = newParent
        } else {
            collection.parent = nil
        }
        collection.colorHex = colorHex
        collection.iconName = iconName

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
        sidebarSelectionContext = .collection(collection.persistentModelID)
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
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
        Menu("Copy to") {
            ForEach(collections) { collection in
                Button { copySnippet(snippet, to: collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSnippetRow(for snippet: Snippet, context: SidebarSelectionContext) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = context
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
