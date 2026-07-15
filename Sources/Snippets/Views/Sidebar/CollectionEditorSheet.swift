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

    private static let symbolSections: [SymbolSection] = [
        .init(title: "Development", symbols: [
            "curlybraces", "terminal", "chevron.left.forwardslash.chevron.right", "command",
            "apple.terminal", "function", "number", "sum",
            "at", "cpu", "memorychip", "server.rack",
            "desktopcomputer", "laptopcomputer", "keyboard", "display",
            "apple.logo", "swift", "gearshape.2", "wrench.and.screwdriver",
            "hammer", "ant", "ladybug", "testtube.2"
        ]),
        .init(title: "Cloud & Data", symbols: [
            "externaldrive", "internaldrive", "network", "point.3.connected.trianglepath.dotted",
            "cloud", "cloud.fill", "icloud", "arrow.up.arrow.down",
            "doc.plaintext", "doc.text", "doc.on.doc", "folder",
            "folder.badge.gearshape", "tray.full", "archivebox", "cylinder",
            "cylinder.split.1x2", "opticaldiscsymbol", "sdcard", "filemenu.and.selection"
        ]),
        .init(title: "Design & Media", symbols: [
            "paintbrush", "paintpalette", "wand.and.stars", "sparkles",
            "camera", "photo", "rectangle.3.group", "square.grid.3x3",
            "eyedropper", "ruler", "pencil.and.ruler", "scissors",
            "play.rectangle", "waveform", "music.note", "video",
            "rectangle.on.rectangle", "square.on.square", "circle.grid.3x3", "aspectratio"
        ]),
        .init(title: "Security & Networking", symbols: [
            "lock", "lock.shield", "key", "lock.circle",
            "wifi", "antenna.radiowaves.left.and.right", "globe", "globe.americas",
            "link", "personalhotspot", "bolt.horizontal", "arrow.triangle.branch",
            "tag", "bookmark", "pin", "flag",
            "bell", "paperclip", "scope", "eye"
        ])
    ]

    private static let validatedSymbolSections: [SymbolSection] = {
        symbolSections.compactMap { section in
            let symbols = section.symbols.filter(SnippetCollection.isValidSFSymbolName)
            guard !symbols.isEmpty else { return nil }
            return SymbolSection(title: section.title, symbols: symbols)
        }
    }()

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
        return Self.validatedSymbolSections.compactMap { section in
            let symbols = section.symbols.filter { symbol in
                needle.isEmpty || symbol.lowercased().contains(needle)
            }
            guard !symbols.isEmpty else { return nil }
            return SymbolSection(title: section.title, symbols: symbols)
        }
    }

    private enum ContrastSuggestion {
        /// Color has poor contrast in the current mode → best for the other mode
        case poorInCurrent(suggested: Color, otherModeName: String)
        /// Color works in current mode but poorly in the other
        case poorInOther(suggested: Color, otherModeName: String)
        case none
    }

    private var contrastSuggestion: ContrastSuggestion {
        // Once the user has set separate colors, don't suggest anymore
        guard collectionColorDark == nil else { return .none }

        let current = activeColor
        let contrastWithLight = current.contrastRatio(with: Color.white)
        let contrastWithDark = current.contrastRatio(with: Color(white: 0.1))

        if colorScheme == .light {
            if contrastWithLight < 2.5 {
                // Too light for light mode → best used in dark mode
                return .poorInCurrent(
                    suggested: current.brightness(-0.25).saturation(1.2),
                    otherModeName: "Dark"
                )
            } else if contrastWithDark < 2.5 {
                // Good in light, poor in dark
                return .poorInOther(
                    suggested: current.brightness(0.3).saturation(0.8),
                    otherModeName: "Dark"
                )
            }
        } else {
            if contrastWithDark < 2.5 {
                // Too dark for dark mode → best used in light mode
                return .poorInCurrent(
                    suggested: current.brightness(0.3).saturation(0.8),
                    otherModeName: "Light"
                )
            } else if contrastWithLight < 2.5 {
                // Good in dark, poor in light
                return .poorInOther(
                    suggested: current.brightness(-0.25).saturation(1.2),
                    otherModeName: "Light"
                )
            }
        }
        return .none
    }

    @ViewBuilder
    private var glassContrastWarning: some View {
        let currentModeName = colorScheme == .light ? "Light" : "Dark"

        switch contrastSuggestion {
        case .poorInCurrent(let suggested, let otherModeName):
            contrastWarningCard(
                text: "Poor contrast in \(currentModeName) Mode. Best used in \(otherModeName) Mode.",
                suggestionText: "Use for \(otherModeName) & apply adjusted version for \(currentModeName)",
                suggestedColor: suggested
            ) {
                if colorScheme == .light {
                    // Keep original for dark, apply darker suggestion for light
                    collectionColorDark = collectionColor
                    collectionColor = suggested
                } else {
                    // Keep original for light, apply lighter suggestion for dark
                    collectionColorDark = suggested
                }
            }
        case .poorInOther(let suggested, let otherModeName):
            contrastWarningCard(
                text: "Looks great in \(currentModeName) Mode, but has poor contrast in \(otherModeName) Mode.",
                suggestionText: "Apply adjusted version for \(otherModeName) Mode",
                suggestedColor: suggested
            ) {
                if colorScheme == .light {
                    collectionColorDark = suggested
                } else {
                    let currentDark = collectionColor
                    collectionColor = suggested
                    collectionColorDark = currentDark
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func contrastWarningCard(text: String, suggestionText: String, suggestedColor: Color, action: @escaping () -> Void) -> some View {
        let otherColorBinding = Binding<Color>(
            get: {
                colorScheme == .light ? (collectionColorDark ?? collectionColor) : collectionColor
            },
            set: { newColor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if colorScheme == .light {
                        collectionColorDark = newColor
                    } else {
                        let currentDark = collectionColorDark ?? collectionColor
                        collectionColor = newColor
                        collectionColorDark = currentDark
                    }
                }
            }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                // Auto-suggested color button
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

                // Custom color picker for the other mode
                ColorPicker("Adjust Brightness", selection: otherColorBinding, supportsOpacity: false)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, -12)
        .padding(.bottom, -4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            ScrollView {
                DSGlassContainer(spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        glassPreviewHeader
                        glassColorStrip

                        glassContrastWarning

                        glassSubcollectionToggleSection
                        glassSnippetMembershipSection
                        glassSymbolBrowser
                    }
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
        .frame(width: 480, height: 640)
    }

    // MARK: - Liquid Glass Header

    private var editorHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: previewIconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(activeColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: activeColor.opacity(0.1),
                shadowRadius: 4,
                shadowY: 2
            )

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
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

            Button(action: onSave) {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSave ? .white : theme.textFaint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canSave ? activeColor : Color.clear)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: canSave ? activeColor.opacity(0.2) : nil,
                interactive: true,
                shadowRadius: 4,
                shadowY: 2
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Liquid Glass Preview Header

    private var glassPreviewHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                if collectionColorDark != nil {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        VStack(spacing: 4) {
                            Text("Light").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                            previewIcon(color: collectionColor, isDark: false)
                        }
                        VStack(spacing: 4) {
                            Text("Dark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                            previewIcon(color: collectionColorDark!, isDark: true)
                        }
                    }
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            collectionColorDark = nil
                        }
                    } label: {
                        Text("Reset to unified")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            } else {
                previewIcon(color: activeColor, isDark: colorScheme == .dark)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: collectionColorDark)

            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
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
                            .fill((Color(hex: choice.hex) ?? theme.accent).opacity(0.35))
                            .frame(width: 38, height: 38)
                            .blur(radius: 6)
                            .opacity(isSelected ? 1 : 0)

                        Circle()
                            .fill(Color(hex: choice.hex) ?? theme.accent)
                            .frame(width: 28, height: 28)

                        Circle()
                            .strokeBorder(.white, lineWidth: 2.5)
                            .frame(width: 28, height: 28)
                            .opacity(isSelected ? 1 : 0)
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
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay {
                        ZStack {
                            Circle()
                                .fill(activeColor.opacity(1.0)) // ensure full coverage
                            Circle()
                                .fill(theme.surface) // background to hide the color well underneath completely
                            Circle()
                                .fill(activeColor.opacity(0.15))
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                        center: .center
                                    ),
                                    lineWidth: 2.0
                                )
                        }
                        .frame(width: 28, height: 28)
                        .allowsHitTesting(false)
                    }
            }
            .frame(width: 38, height: 38)
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

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 40), spacing: 8)], spacing: 8) {
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
        .padding(DSToken.Spacing.md)
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
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(activeColor)
                            .shadow(color: isSelected ? activeColor.opacity(0.5) : .clear, radius: 6, x: 0, y: 2)
                            .opacity(isSelected ? 1 : 0)
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
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
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
                    Spacer(minLength: 12)
                    Picker("", selection: $parentCollectionID) {
                        Text("Select collection…").tag(Optional<PersistentIdentifier>.none)
                        ForEach(availableParentCollections) { collection in
                            Text(collection.name).tag(Optional(collection.persistentModelID))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .trailing)
                    .tint(activeColor)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(DSToken.Spacing.md)
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
        let lookup = Dictionary(uniqueKeysWithValues: collections.map { ($0.persistentModelID, $0) })

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            if let current = lookup[currentID] {
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
        .padding(DSToken.Spacing.md)
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
                        .fill(.thickMaterial)
                        .frame(width: 20, height: 20)

                    Circle()
                        .fill(activeColor)
                        .frame(width: 20, height: 20)
                        .opacity(isSelected ? 1 : 0)

                    Circle()
                        .stroke(
                            isSelected
                                ? activeColor
                                : .white.opacity(colorScheme == .dark ? 0.1 : 0.2),
                            lineWidth: 1
                        )
                        .frame(width: 20, height: 20)

                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(isSelected ? 1 : 0.5)
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
