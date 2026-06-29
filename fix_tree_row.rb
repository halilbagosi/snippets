require 'fileutils'
content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

old_tree_row = <<-SWIFT
    private func snippetRow(_ snippet: Snippet) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent

        return Label {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(ModernSidebar.Selection.snippet(snippet.persistentModelID, .collection(collection.persistentModelID)))
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
SWIFT

new_tree_row = <<-SWIFT
    private func snippetRow(_ snippet: Snippet) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent

        return Label {
            Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(ModernSidebar.Selection.snippet(snippet.persistentModelID, .collection(collection.persistentModelID)))
        .tint(accent)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
SWIFT

content = content.sub(old_tree_row.strip, new_tree_row.strip)
File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
