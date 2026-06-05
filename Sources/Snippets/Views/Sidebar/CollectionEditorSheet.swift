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
    @Binding var collectionColorDark: Color?
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
        .init(name: "Red", hex: "#DC2626"),
        .init(name: "Orange", hex: "#EA580C"),
        .init(name: "Yellow", hex: "#CA8A04"),
        .init(name: "Green", hex: "#16A34A"),
        .init(name: "Blue", hex: "#2563EB"),
        .init(name: "Purple", hex: "#9333EA"),
        .init(name: "Pink", hex: "#DB2777"),
        .init(name: "Gray", hex: "#4B5563")
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
    private var activeColor: Color {
        colorScheme == .dark ? (collectionColorDark ?? collectionColor) : collectionColor
    }

    private var activeColorBinding: Binding<Color> {
        Binding {
            activeColor
        } set: { newColor in
            if colorScheme == .dark {
                collectionColorDark = newColor
                // Reset light to match so contrast suggestion can re-trigger
                collectionColor = newColor
            } else {
                collectionColor = newColor
                // Reset dark to nil so contrast suggestion can re-trigger
                collectionColorDark = nil
            }
        }
    }

    private var selectedColorHex: String { activeColor.hexString(fallback: SnippetCollection.defaultColorHex).lowercased() }

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

    private enum ContrastSuggestion {
        case suggestForDark(Color)
        case suggestForLight(Color)
        case none
    }

    private var contrastSuggestion: ContrastSuggestion {
        let current = activeColor
        if colorScheme == .light {
            // Check if the current light color has poor contrast in dark mode
            if current.contrastRatio(with: Color(white: 0.1)) < 2.5 {
                return .suggestForDark(current.brightness(0.3).saturation(0.8))
            }
        } else {
            // Check if the current dark color has poor contrast in light mode
            if current.contrastRatio(with: Color.white) < 2.5 {
                return .suggestForLight(current.brightness(-0.25).saturation(1.2))
            }
        }
        return .none
    }

    @ViewBuilder
    private var glassContrastWarning: some View {
        switch contrastSuggestion {
        case .suggestForDark(let suggested):
            warningView(
                text: "This color looks great in Light Mode, but has poor contrast in Dark Mode.",
                suggestionText: "Apply Lighter Version to Dark Mode",
                suggestedColor: suggested
            ) {
                collectionColorDark = suggested
            }
        case .suggestForLight(let suggested):
            warningView(
                text: "This color looks great in Dark Mode, but has poor contrast in Light Mode.",
                suggestionText: "Apply Darker Version to Light Mode",
                suggestedColor: suggested
            ) {
                let currentDark = collectionColorDark ?? collectionColor
                collectionColor = suggested
                collectionColorDark = currentDark
            }
        case .none:
            EmptyView()
        }
    }

    private func warningView(text: String, suggestionText: String, suggestedColor: Color, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    action()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(suggestedColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                    Text(suggestionText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, -12)
        .padding(.bottom, -4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        glassPreviewHeader
                        glassColorStrip

                        glassContrastWarning
                        
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
                    DotGridBackground(gradientPalette: [activeColor], lightModeStrength: 0.5)
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
                        .tint(activeColor)
                }
            }
        }
        .frame(width: 480, height: 640)
    }

    // MARK: - Liquid Glass Preview Header

    private var glassPreviewHeader: some View {
        HStack(spacing: 16) {
            if collectionColorDark != nil {
                HStack(spacing: 8) {
                    previewIcon(color: collectionColor, isDark: false)
                    previewIcon(color: collectionColorDark!, isDark: true)
                }
            } else {
                previewIcon(color: activeColor, isDark: colorScheme == .dark)
            }

            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
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
                let isSelected = selectedColorHex == choice.hex.lowercased()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let newColor = Color(hex: choice.hex) {
                            // Palette colors set a single color for both modes
                            collectionColor = newColor
                            collectionColorDark = nil
                        }
                    }
                } label: {
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
                ColorPicker("", selection: activeColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.015)
                    .clipShape(Circle())

                Circle()
                    .fill(activeColor)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle().stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.25), lineWidth: 1)
                    }
                    .allowsHitTesting(false)

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .allowsHitTesting(false)
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .clipShape(Circle())
            .help("Custom color")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .liquidGlassSurface(
            in: Capsule(style: .continuous),
            tint: activeColor.opacity(0.15),
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
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            shadowRadius: 12,
            shadowY: 6
        )
    }

    private func previewIcon(color: Color, isDark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDark ? Color(white: 0.15) : Color.white)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(isDark ? 0.15 : 0.1))
            
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(isDark ? 0.3 : 0.2), lineWidth: 1)
            
            Image(systemName: SnippetCollection.isValidSFSymbolName(collectionIconName) ? collectionIconName : SnippetCollection.defaultIconName)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .frame(width: 56, height: 56)
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
                            .fill(activeColor)
                            .shadow(color: activeColor.opacity(0.5), radius: 6, x: 0, y: 2)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected
                                ? activeColor.opacity(0.6)
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
                        .foregroundStyle(activeColor)
                }
                Spacer()
                Toggle("", isOn: $isSubcollection.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(activeColor)
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
                    .tint(activeColor)
                    .frame(maxWidth: 200)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(16)
        .background {
            Color.clear
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    shadowRadius: 8,
                    shadowY: 4
                )
        }
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
                            .foregroundStyle(activeColor)
                    }
                    Spacer()
                    Text("\(selectedSnippetIDs.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(activeColor)
                                .shadow(color: activeColor.opacity(0.3), radius: 4, x: 0, y: 2)
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
        .background {
            Color.clear
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    shadowRadius: 8,
                    shadowY: 4
                )
        }
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
                        .fill(isSelected ? AnyShapeStyle(activeColor) : AnyShapeStyle(.thickMaterial))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .stroke(
                                    isSelected
                                        ? activeColor
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
                    .fill(isSelected ? activeColor.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
