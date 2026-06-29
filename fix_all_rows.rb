require 'fileutils'
content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# 1. Fix countRow
count_row_old = <<-SWIFT
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? iconColor.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
                .padding(.horizontal, 8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT
content = content.sub(count_row_old.strip, count_row_new.strip)

# 2. Fix countRow in CollectionTreeRow
tree_count_old = <<-SWIFT
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor

        return HStack {
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

tree_count_new = <<-SWIFT
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor

        return HStack {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? iconColor.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
                .padding(.horizontal, 8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT
content = content.sub(tree_count_old.strip, tree_count_new.strip)

# 3. Fix snippetRow in CollectionTreeRow
tree_snippet_old = <<-SWIFT
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

tree_snippet_new = <<-SWIFT
    private func snippetRow(_ snippet: Snippet) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent

        return Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = .collection(collection.persistentModelID)
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            Label {
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
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
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
SWIFT
content = content.sub(tree_snippet_old.strip, tree_snippet_new.strip)

File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
