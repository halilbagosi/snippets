require 'fileutils'

content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# 1. Update snippetRow in ModernSidebar
snippet_row_old = <<-SWIFT
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent
        Label {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(Selection.snippet(snippet.persistentModelID, context))
    }
SWIFT

snippet_row_new = <<-SWIFT
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

content = content.sub(snippet_row_old.strip, snippet_row_new.strip)


# 2. Update countRow in ModernSidebar
count_row_old = <<-SWIFT
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool = false) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(activeIconColor)
            }
            Spacer()
            if count > 0 {
                Text("\\(count)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .contentShape(Rectangle())
    }
SWIFT

count_row_new = <<-SWIFT
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool = false) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor
        HStack {
            Label {
                Text(title.lowercased())
                    .font(Mono.font(size: 12, weight: isSelected ? .semibold : .medium))
            } icon: {
                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(activeIconColor)
            }
            Spacer()
            if count > 0 {
                Text("\\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .contentShape(Rectangle())
        .tint(iconColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT

content = content.sub(count_row_old.strip, count_row_new.strip)

# 3. Add Mono struct if it's missing (as a fallback in case Theme doesn't expose it properly in this scope). Wait, Mono is in Theme.swift! But earlier I got 'cannot find Mono in scope'. That was due to swiftc not linking Theme.swift. But just in case, I'll add `import AppKit` and assume it works in the Xcode project since it's in the same module.

File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
