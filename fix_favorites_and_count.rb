require 'fileutils'

content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# 1. favoritesSection favoriteCollections
fav_coll_old = <<-SWIFT
                Label {
                    Text(collection.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : Color(red: 1.0, green: 0.80, blue: 0.20))
                }
                .tag(Selection.favoriteCollection(collection.persistentModelID))
SWIFT

fav_coll_new = <<-SWIFT
                let accent = Color(red: 1.0, green: 0.80, blue: 0.20)
                Label {
                    Text(collection.name.lowercased())
                        .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent)
                }
                .tag(Selection.favoriteCollection(collection.persistentModelID))
                .tint(accent)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
SWIFT
content = content.sub(fav_coll_old.strip, fav_coll_new.strip)

# 2. favoritesSection favoriteSnippets
fav_snip_old = <<-SWIFT
                Label {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : Color(red: 1.0, green: 0.80, blue: 0.20))
                }
                .tag(Selection.snippet(snippet.persistentModelID, .favorites))
SWIFT

fav_snip_new = <<-SWIFT
                let accent = Color(red: 1.0, green: 0.80, blue: 0.20)
                Label {
                    Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                        .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent)
                }
                .tag(Selection.snippet(snippet.persistentModelID, .favorites))
                .tint(accent)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
SWIFT
content = content.sub(fav_snip_old.strip, fav_snip_new.strip)

# 3. CollectionTreeRow countRow
tree_count_old = <<-SWIFT
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor

        return HStack {
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
        .contentShape(Rectangle())
        .tint(iconColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
SWIFT
content = content.sub(tree_count_old.strip, tree_count_new.strip)

File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
