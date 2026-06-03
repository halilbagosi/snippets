import SwiftUI
import SwiftData

struct CollectionEditorSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    var title: String {
        editingCollection == nil ? "New collection" : "Edit collection"
    }

    private struct SymbolSection: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    private struct ColorChoice: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    @Binding var collectionName: String
    @Binding var collectionColor: Color
    @Binding var collectionIconName: String
    @Binding var selectedSnippetIDs: Set<PersistentIdentifier>
    @Binding var parentCollectionID: PersistentIdentifier?
    @Binding var isSubcollection: Bool
    @Binding var editingCollection: SnippetCollection?
    
    let snippets: [Snippet]
    let collections: [SnippetCollection]
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var symbolSearch: String = ""
    @State private var isSnippetPickerExpanded: Bool = false

    private let palette: [ColorChoice] = [
        .init(name: "Red", hex: "#FF453A"),
        .init(name: "Orange", hex: "#FF9F0A"),
        .init(name: "Yellow", hex: "#FFD60A"),
        .init(name: "Green", hex: "#30D158"),
        .init(name: "Blue", hex: "#0A84FF"),
        .init(name: "Purple", hex: "#BF5AF2"),
        .init(name: "Pink", hex: "#FF375F"),
        .init(name: "Gray", hex: "#8E8E93")
    ]

    private let symbolSections: [SymbolSection] = [
        .init(title: "Code", symbols: [
            "curlybraces", "terminal", "chevron.left.forwardslash.chevron.right", "command",
            "apple.terminal", "doc.plaintext", "doc.text", "doc.on.doc",
            "text.alignleft", "number", "function", "sum",
            "at", "cpu", "memorychip", "server.rack",
            "externaldrive", "internaldrive", "network", "point.3.connected.trianglepath.dotted"
        ]),
        .init(title: "Objects", symbols: [
            "tag", "bookmark", "paperclip", "link",
            "pin", "archivebox", "tray.full", "shippingbox",
            "lock", "key", "hammer", "wrench.and.screwdriver",
            "paintpalette", "wand.and.stars", "camera", "photo",
            "video", "play.rectangle", "music.note", "waveform"
        ]),
        .init(title: "People", symbols: [
            "person", "person.fill", "person.2", "person.2.fill",
            "person.crop.circle", "person.crop.circle.fill", "figure.stand", "figure.walk",
            "figure.wave", "figure.2.and.child.holdinghands", "person.3", "person.3.fill",
            "brain.head.profile", "eye", "eyes", "ear",
            "hand.raised", "hand.thumbsup", "hand.thumbsdown", "hand.tap",
            "hand.point.up.left", "hand.point.right", "hand.wave", "face.smiling"
        ]),
        .init(title: "Animals & Nature", symbols: [
            "hare", "tortoise", "dog", "cat",
            "bird", "fish", "pawprint", "ladybug",
            "leaf", "tree", "globe.americas", "globe.europe.africa",
            "sun.max", "sunrise", "sunset", "moon",
            "sparkles", "cloud", "flame", "drop"
        ])
    ]

    private var theme: Theme { Theme.current(colorScheme) }

    private var trimmedName: String { collectionName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedIconName: String { collectionIconName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSymbolValid: Bool { SnippetCollection.isValidSFSymbolName(trimmedIconName) }
    private var previewIconName: String { isSymbolValid ? trimmedIconName : SnippetCollection.defaultIconName }
    private var canSave: Bool { !trimmedName.isEmpty && isSymbolValid }
    private var selectedColorHex: String { collectionColor.hexString(fallback: SnippetCollection.defaultColorHex).lowercased() }

    private var displayedSymbolSections: [SymbolSection] {
        let needle = symbolSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return symbolSections.compactMap { section in
            let symbols = section.symbols.filter { symbol in
                SnippetCollection.isValidSFSymbolName(symbol) &&
                (needle.isEmpty || symbol.lowercased().contains(needle))
            }
            guard !symbols.isEmpty else { return nil }
            return SymbolSection(title: section.title, symbols: symbols)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        glassPreviewHeader
                        glassColorStrip
                        
                        glassSubcollectionToggleSection
                        glassSnippetMembershipSection
                        glassSymbolBrowser
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .background {
                ZStack {
                    Color.clear.ignoresSafeArea()
                    DotGridBackground(gradientPalette: [collectionColor], lightModeStrength: 0.5)
                        .opacity(colorScheme == .dark ? 0.12 : 0.10)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(!canSave)
                        .tint(collectionColor)
                }
            }
        }
        .frame(width: 480, height: 640)
    }

    // MARK: - Liquid Glass Preview Header

    private var glassPreviewHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(collectionColor.opacity(colorScheme == .dark ? 0.15 : 0.10))
                    .frame(width: 80, height: 80)
                    .blur(radius: 12)

                CollectionIconView(
                    iconName: previewIconName,
                    color: collectionColor,
                    size: 56,
                    isSelected: true
                )
            }
            .frame(height: 68)

            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: 280)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.3), lineWidth: 1)
                        }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Liquid Glass Color Strip

    private var glassColorStrip: some View {
        HStack(spacing: 10) {
            ForEach(palette) { choice in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        collectionColor = Color(hex: choice.hex) ?? collectionColor
                    }
                } label: {
                    let isSelected = selectedColorHex == choice.hex.lowercased()
                    ZStack {
                        Circle()
                            .fill(Color(hex: choice.hex) ?? theme.accent)
                            .frame(width: 28, height: 28)

                        if isSelected {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2.5)
                                .frame(width: 28, height: 28)

                            Circle()
                                .fill((Color(hex: choice.hex) ?? theme.accent).opacity(0.35))
                                .frame(width: 38, height: 38)
                                .blur(radius: 6)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                }
                .buttonStyle(.plain)
                .help(choice.name)
            }

            ZStack {
                Circle()
                    .fill(collectionColor)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle().stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.25), lineWidth: 1)
                    }

                ColorPicker("Custom Color", selection: $collectionColor, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(3.0)
                    .opacity(0.015)

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .allowsHitTesting(false)
            }
            .frame(width: 38, height: 38)
            .help("Custom color")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .liquidGlassSurface(
            in: Capsule(style: .continuous),
            tint: collectionColor.opacity(0.15),
            shadowRadius: 8,
            shadowY: 4
        )
    }

    // MARK: - Liquid Glass Symbol Browser

    private var glassSymbolBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search SF Symbols", text: $symbolSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !symbolSearch.isEmpty {
                    Button {
                        symbolSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.2), lineWidth: 1)
                    }
            }

            ForEach(displayedSymbolSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 32, maximum: 40), spacing: 8), count: 8), spacing: 8) {
                        ForEach(section.symbols, id: \.self) { symbolName in
                            glassSymbolButton(symbolName)
                        }
                    }
                }
                .padding(.top, 6)
            }

            if displayedSymbolSections.isEmpty {
                Text("No matching symbols")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(16)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private func glassSymbolButton(_ symbolName: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                collectionIconName = symbolName
            }
        } label: {
            let isSelected = previewIconName == symbolName
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle()
                            .fill(collectionColor)
                            .shadow(color: collectionColor.opacity(0.5), radius: 6, x: 0, y: 2)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected
                                ? collectionColor.opacity(0.6)
                                : .white.opacity(colorScheme == .dark ? 0.06 : 0.15),
                            lineWidth: 1
                        )
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .help(symbolName)
    }

    // MARK: - Liquid Glass Subcollection Toggle

    private var glassSubcollectionToggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("Sub-Collection")
                        .font(.system(size: 14, weight: .semibold))
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(collectionColor)
                }
                Spacer()
                Toggle("", isOn: $isSubcollection.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(collectionColor)
            }

            if isSubcollection {
                HStack {
                    Text("Collection")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $parentCollectionID) {
                        Text("Select collection…").tag(nil as PersistentIdentifier?)
                        ForEach(availableParentCollections) { collection in
                            Text(collection.name).tag(collection.persistentModelID as PersistentIdentifier?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(collectionColor)
                    .frame(maxWidth: 200)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(16)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            shadowRadius: 8,
            shadowY: 4
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSubcollection)
    }

    private var availableParentCollections: [SnippetCollection] {
        guard let editingID = editingCollection?.persistentModelID else {
            return collections
        }
        var excludedIDs = Set([editingID])
        var queue = [editingID]

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            if let current = collections.first(where: { $0.persistentModelID == currentID }) {
                let childIDs = current.children.map(\.persistentModelID)
                excludedIDs.formUnion(childIDs)
                queue.append(contentsOf: childIDs)
            }
        }

        return collections.filter { !excludedIDs.contains($0.persistentModelID) }
    }

    // MARK: - Liquid Glass Snippet Membership

    private var glassSnippetMembershipSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                    isSnippetPickerExpanded.toggle()
                }
            } label: {
                HStack {
                    Label {
                        Text("Snippets")
                            .font(.system(size: 14, weight: .semibold))
                    } icon: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(collectionColor)
                    }
                    Spacer()
                    Text("\(selectedSnippetIDs.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(collectionColor)
                                .shadow(color: collectionColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSnippetPickerExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSnippetPickerExpanded {
                if snippets.isEmpty {
                    Text("No snippets yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .padding(.top, 4)
                        .transition(.opacity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(snippets) { snippet in
                            glassSnippetToggleRow(snippet)
                        }
                    }
                    .padding(.top, 16)
                    .transition(.opacity)
                }
            }
        }
        .padding(16)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private func glassSnippetToggleRow(_ snippet: Snippet) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if selectedSnippetIDs.contains(snippet.persistentModelID) {
                    selectedSnippetIDs.remove(snippet.persistentModelID)
                } else {
                    selectedSnippetIDs.insert(snippet.persistentModelID)
                }
            }
        } label: {
            let isSelected = selectedSnippetIDs.contains(snippet.persistentModelID)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(collectionColor) : AnyShapeStyle(.thickMaterial))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .stroke(
                                    isSelected
                                        ? collectionColor
                                        : .white.opacity(colorScheme == .dark ? 0.1 : 0.2),
                                    lineWidth: 1
                                )
                        }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    let lang = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                    Text(lang.rawValue.lowercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? collectionColor.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
