import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct SnippetGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let snippets: [Snippet]
    let collectionMatchSnippets: [Snippet]
    let contentMatchSnippets: [Snippet]
    let searchQuery: String
    @Binding var searchText: String
    @Binding var selectedLanguage: SupportedLanguage?
    let availableLanguages: [SupportedLanguage]
    let onSelect: (Snippet) -> Void
    let onNew: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var hasAnimatedCards = false
    @State private var fabHovered = false
    @State private var pressedSnippetID: PersistentIdentifier? = nil
#if canImport(AppKit)
    @State private var keyEventMonitor: Any? = nil
#endif

    private let columns = [GridItem(.adaptive(minimum: 420, maximum: 640), spacing: 20)]
    private var hasAnyResults: Bool {
        !snippets.isEmpty || !collectionMatchSnippets.isEmpty || !contentMatchSnippets.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(alignment: .leading, spacing: 22) {
                            if !hasAnyResults {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 36)
                            } else if !searchQuery.isEmpty {
                                if !collectionMatchSnippets.isEmpty {
                                    resultSectionHeader("Snippets in collection \"\(searchQuery)\"")
                                    snippetGrid(collectionMatchSnippets)
                                }
                                if !contentMatchSnippets.isEmpty {
                                    resultSectionHeader("Snippets containing \"\(searchQuery)\"")
                                    snippetGrid(contentMatchSnippets)
                                }
                            } else {
                                snippetGrid(snippets)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        topBar
                    }
                }
            }
            .scrollIndicators(.never)

            fab
                .padding(.trailing, 32)
                .padding(.bottom, 28)
        }
        .onAppear {
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                hasAnimatedCards = true
            }
            #if canImport(AppKit)
            guard keyEventMonitor == nil else { return }
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let chars = event.charactersIgnoringModifiers ?? ""
                if event.modifierFlags.contains(.command), chars.lowercased() == "f" {
                    searchFocused = true
                    return nil
                }
                if event.keyCode == 53 {
                    if searchFocused {
                        searchFocused = false
                        return nil
                    }
                    if !searchText.isEmpty {
                        searchText = ""
                        return nil
                    }
                }
                return event
            }
            #endif
        }
        .onChange(of: snippets.count) { _, _ in
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                hasAnimatedCards = true
            }
        }
        .onDisappear {
            #if canImport(AppKit)
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            #endif
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }

    private func resultSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Mono.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func snippetGrid(_ source: [Snippet]) -> some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(source.enumerated()), id: \.element.persistentModelID) { index, snippet in
                SnippetCard(snippet: snippet)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(pressedSnippetID == snippet.persistentModelID ? 0.97 : 1.0)
                    .opacity(pressedSnippetID == snippet.persistentModelID ? 0.92 : 1.0)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(y: hasAnimatedCards ? 0 : 16)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.86)
                            .delay(min(Double(index) * 0.03, 0.24)),
                        value: hasAnimatedCards
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressedSnippetID)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.11)) {
                            pressedSnippetID = snippet.persistentModelID
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                            onSelect(snippet)
                            withAnimation(.easeOut(duration: 0.14)) {
                                pressedSnippetID = nil
                            }
                        }
                    }
            }
        }
        .padding(.bottom, 112)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            if !availableLanguages.isEmpty {
                filterBar
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.white.opacity(colorScheme == .dark ? 0.10 : 0.34))
                }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(Mono.font(size: 10, weight: .semibold))
                Text("snippets")
                    .font(Mono.font(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.textMuted)

            Text(">")
                .font(Mono.font(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)

            TextField("search title, description, or code…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(Mono.font(size: 13))
                .foregroundStyle(theme.text)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Mono.font(size: 12))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(.plain)
            }

            Text(searchFocused ? "esc" : "⌘F")
                .font(Mono.font(size: 10, weight: .semibold))
                .foregroundStyle(theme.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface.opacity(colorScheme == .dark ? 0.80 : 0.68))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(searchFocused ? theme.accent.opacity(0.5) : theme.border.opacity(0.65), lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterTag(label: "lang:all", icon: "asterisk", accent: theme.accent, isSelected: selectedLanguage == nil) {
                    selectedLanguage = nil
                }
                ForEach(availableLanguages) { language in
                    FilterTag(
                        label: "lang:\(language.rawValue.lowercased())",
                        icon: language.symbolName,
                        accent: Color(hex: language.accentHex) ?? theme.accent,
                        isSelected: selectedLanguage == language
                    ) {
                        selectedLanguage = (selectedLanguage == language) ? nil : language
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("// no snippets yet")
                .font(Mono.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.comment)
            Button { onNew() } label: {
                Text("new snippet")
                    .font(Mono.font(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 480)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface.opacity(0.6)))
    }

    private var fab: some View {
        Button(action: onNew) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(Mono.font(size: 14, weight: .bold))
                Text("new snippet")
                    .font(Mono.font(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background { 
                Capsule(style: .continuous)
                    .fill(theme.accent)
                    .shadow(color: theme.accent.opacity(fabHovered ? 0.6 : 0.0), radius: fabHovered ? 14 : 0, y: fabHovered ? 4 : 0)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .scaleEffect(fabHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fabHovered)
        .onHover { fabHovered = $0 }
    }
}

private struct FilterTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let icon: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Mono.font(size: 10, weight: .semibold))
                Text(label)
                    .font(Mono.font(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : accent)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? accent : accent.opacity(colorScheme == .dark ? 0.12 : 0.10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? .clear : accent.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.12), value: isSelected)
    }
}
