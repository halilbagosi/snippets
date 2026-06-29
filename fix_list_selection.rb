require 'fileutils'

content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# 1. Remove `selection: selection` from List
content = content.sub("List(selection: selection) {", "List {")

# 2. Add Button and background to snippetRow(..., context: ...)
old_snippet_row = <<-SWIFT
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent
        Label {
            Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(Selection.snippet(snippet.persistentModelID, context))
        .tint(accent)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT

new_snippet_row = <<-SWIFT
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent
        Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = context
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            Label {
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Circle()
                    .fill(activeAccent)
                    .frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
                .padding(.horizontal, 8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT
content = content.sub(old_snippet_row.strip, new_snippet_row.strip)


File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
