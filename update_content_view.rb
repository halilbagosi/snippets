require 'fileutils'

content = File.read("Sources/Snippets/Views/ContentView.swift")

# Find the start of `var body: some View {`
# Replace it up to `.task {`

body_start = content.index("    var body: some View {")
task_start = content.index("        .task {", body_start)

if body_start && task_start
  original_body_str = content[body_start...task_start]
  
  new_body = <<-SWIFT
    @ViewBuilder
    private var mainDetailView: some View {
        if sidebarSelectionContext == .trash {
            TrashView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(
                        segments: currentStatusSegments,
                        contentLeadingInset: 0
                    )
                }
        } else {
            ZStack {
                Group {
                    DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78, focusedMode: appearanceSettings.focusedMode)
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    SnippetGalleryView(
                        snippets: gallerySnippets,
                        searchResultCollections: searchResultCollections,
                        searchResultSnippets: searchResultSnippets,
                        searchQuery: trimmedSearchText,
                        searchText: $searchText,
                        showFavoritesOnly: $showFavoritesOnly,
                        selectedLanguages: $selectedLanguages,
                        selectedSearchCollections: $selectedSearchCollections,
                        showUncategorizedOnly: $showUncategorizedOnly,
                        availableLanguages: availableLanguages,
                        availableCollections: collections,
                        subcollections: gallerySubcollections,
                        onSelect: { snippet in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSnippetID = snippet.persistentModelID
                                if let colID = selectedCollectionID {
                                    sidebarSelectionContext = .collection(colID)
                                } else {
                                    sidebarSelectionContext = .allSnippets
                                }
                            }
                        },
                        onSelectCollection: { collection in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSearchCollections.removeAll()
                                selectedSnippetID = nil
                                selectedCollectionID = collection.persistentModelID
                                sidebarSelectionContext = .collection(collection.persistentModelID)
                            }
                        },
                        onCreateCollection: {
                            beginCreateCollection()
                        },
                        onNew: {
                            newSnippetPreselectedCollectionID = selectedCollectionID
                            isPresentingNew = true
                        },
                        onBack: selectedCollectionID != nil ? {
                            navigateBackFromCollection()
                        } : nil,
                        onClearSelection: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSearchCollections.removeAll()
                                showUncategorizedOnly = false
                                if selectedCollectionID == nil {
                                    sidebarSelectionContext = .allSnippets
                                }
                            }
                        },
                        onEditCollection: { collection in beginEditCollection(collection) },
                        onDeleteCollection: { collection in delete(collection) },
                        onEditSnippet: { snippet in editingSnippet = snippet },
                        onDelete: { snippet, onConfirmed in delete(snippet, onConfirmed: onConfirmed) },
                        onUndoDelete: { undoLastDeletion() },
                        onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
                        onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
                        onMoveCollectionToLibrary: { collection in moveCollectionToLibrary(collection) },
                        onMoveCollectionToCollection: { collection, target in moveCollection(collection, to: target) },
                        onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) }
                    )
                    .blur(radius: selectedSnippet == nil ? 0 : 2)
                    .saturation(selectedSnippet == nil ? 1.0 : 0.95)
                    .allowsHitTesting(selectedSnippet == nil)
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

                if isPresentingNew {
                    Color.black
                        .opacity(colorScheme == .dark ? 0.34 : 0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            NotificationCenter.default.post(name: .init("AttemptDismissEditor"), object: nil)
                        }
                        .transition(.opacity)
                        .zIndex(3)

                    GeometryReader { proxy in
                        let w = min(max(proxy.size.width * 0.90, 820), 1200)
                        let h = min(max(proxy.size.height * 0.92, 660), 960)
                        SnippetEditorView(
                            mode: .create(preselectedCollectionID: newSnippetPreselectedCollectionID),
                            availableCollections: collections,
                            onRequestDismiss: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                    isPresentingNew = false
                                }
                            },
                            onSave: { newSnippet in
                                modelContext.insert(newSnippet)
                                try? modelContext.save()
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    selectedSnippetID = newSnippet.persistentModelID
                                    sidebarSelectionContext = .allSnippets
                                    isPresentingNew = false
                                }
                            }
                        )
                        .frame(width: w, height: h)
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
                                removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                            )
                        )
                    }
                    .zIndex(4)
                }

                if showUndoToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Text(undoToastMessage)
                                .foregroundStyle(theme.text)
                            Button("Undo") {
                                withAnimation {
                                    _ = undoLastDeletion()
                                    showUndoToast = false
                                }
                            }
                            .bold()
                            .foregroundStyle(theme.accent)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.surfaceElevated)
                                .shadow(radius: 10, y: 5)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(theme.borderStrong, lineWidth: 1)
                                }
                        }
                        .padding(.bottom, 60)
                    }
                    .zIndex(100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: selectedSnippetID)
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isPresentingNew)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBar(
                    segments: currentStatusSegments,
                    contentLeadingInset: 0
                )
            }
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                TabView(selection: $sidebarSelectionContext) {
                    Tab("All Snippets", systemImage: "square.grid.2x2", value: SidebarSelectionContext.allSnippets as SidebarSelectionContext?) {
                        mainDetailView
                    }
                    
                    if !topLevelCollections.isEmpty {
                        TabSection("Collections") {
                            ForEach(topLevelCollections) { collection in
                                Tab(collection.name, systemImage: collection.displayIconName, value: SidebarSelectionContext.collection(collection.persistentModelID) as SidebarSelectionContext?) {
                                    mainDetailView
                                }
                            }
                        }
                    }
                    
                    if !favoriteCollections.isEmpty {
                        TabSection("Favorites") {
                            ForEach(favoriteCollections) { collection in
                                Tab(collection.name, systemImage: collection.displayIconName, value: SidebarSelectionContext.favoriteCollection(collection.persistentModelID) as SidebarSelectionContext?) {
                                    mainDetailView
                                }
                            }
                        }
                    }
                    
                    Tab("Trash", systemImage: "trash", value: SidebarSelectionContext.trash as SidebarSelectionContext?) {
                        mainDetailView
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                } detail: {
                    mainDetailView
                }
            }
        }
SWIFT

  new_content = content.sub(original_body_str, new_body)
  File.write("Sources/Snippets/Views/ContentView.swift", new_content)
  puts "Updated ContentView body."
else
  puts "Failed to find body_start or task_start."
end
