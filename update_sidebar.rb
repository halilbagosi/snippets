require 'fileutils'

content = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# Find the start of the body
body_start = content.index("    var body: some View {")
body_end = content.index("    // MARK: - Search Bar")

if body_start && body_end
  original_body = content[body_start...body_end]
  
  new_body = <<-SWIFT
    var body: some View {
        List {
            sidebarSearchBar
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)

            newCollectionButton
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)

            librarySection
            
            if !topLevelCollections.isEmpty {
                collectionsSection
            }

            if !favoriteSnippets.isEmpty || !favoriteCollections.isEmpty {
                favoritesSection
            }

            if !frequentlyUsedSnippets.isEmpty {
                frequentlyUsedSection
            }

            if !availableLanguages.isEmpty {
                languagesSection
            }

            sidebarRow(
                icon: "trash",
                title: "recently deleted",
                count: trashedItemCount,
                isActive: sidebarSelectionContext == .trash,
                accent: .red
            ) {
                sidebarSelectionContext = .trash
                selectedSnippetID = nil
                selectedCollectionID = nil
                selectedLanguages.removeAll()
                selectedSearchCollections.removeAll()
            }
            
            sidebarFooter
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden) // Ensure we get the native translucent background, but wait, native sidebar automatically applies it.
        .background(
            DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.72)
                .opacity(0.45)
                .ignoresSafeArea()
        )
    }

SWIFT

  new_content = content.sub(original_body, new_body)
  File.write("Sources/Snippets/Views/Sidebar/ModernSidebar.swift", new_content)
  puts "Updated ModernSidebar body."
else
  puts "Failed to find body."
end
