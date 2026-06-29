require 'fileutils'
content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# 1. favoriteCollections
fav_coll_old = <<-SWIFT
                let isSelected = selection.wrappedValue == .favoriteCollection(collection.persistentModelID)
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
                .contextMenu {
SWIFT

fav_coll_new = <<-SWIFT
                let isSelected = selection.wrappedValue == .favoriteCollection(collection.persistentModelID)
                let accent = Color(red: 1.0, green: 0.80, blue: 0.20)
                Button {
                    selectedCollectionID = collection.persistentModelID
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    sidebarSelectionContext = .favoriteCollection(collection.persistentModelID)
                } label: {
                    Label {
                        Text(collection.name.lowercased())
                            .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                            .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent)
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
                .contextMenu {
SWIFT
content = content.sub(fav_coll_old.strip, fav_coll_new.strip)

# 2. favoriteSnippets
fav_snip_old = <<-SWIFT
                let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .favorites
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

fav_snip_new = <<-SWIFT
                let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .favorites
                let accent = Color(red: 1.0, green: 0.80, blue: 0.20)
                Button {
                    selectedSnippetID = snippet.persistentModelID
                    selectedCollectionID = nil
                    sidebarSelectionContext = .favorites
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
                        Image(systemName: "star.fill")
                            .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent)
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
SWIFT
content = content.sub(fav_snip_old.strip, fav_snip_new.strip)

File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", content)
