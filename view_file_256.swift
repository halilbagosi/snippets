Created At: 2026-05-24T14:53:32Z
Completed At: 2026-05-24T14:53:32Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1167
Total Bytes: 51065
Showing lines 1 to 60
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1: import SwiftUI
2: import SwiftData
3: 
4: struct ContentView: View {
5:     @Environment(\.modelContext) private var modelContext
6:     @Environment(\.colorScheme) private var colorScheme
7: 
8:     @Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
9:     private var snippets: [Snippet]
10:     @Query(sort: [SortDescriptor(\SnippetCollection.updatedAt, order: .reverse)])
11:     private var collections: [SnippetCollection]
12: 
13:     @State private var selectedLanguage: SupportedLanguage? = nil
14:     @State private var searchText: String = ""
15:     @State private var editingSnippet: Snippet? = nil
16:     @State private var isPresentingNew: Bool = false
17:     @State private var isPresentingCollectionEditor: Bool = false
18:     @State private var editingCollection: SnippetCollection? = nil
19:     @State private var collectionDraftName: String = ""
20:     @State private var collectionDraftSnippetIDs: Set<PersistentIdentifier> = []
21:     @State private var selectedSnippetID: PersistentIdentifier? = nil
22:     enum SidebarSelectionContext: Hashable {
23:         case recent
24:         case allSnippets
25:         case collection(PersistentIdentifier)
26:     }
27:     @State private var sidebarSelectionContext: SidebarSelectionContext? = nil
28:     @State private var selectedCollectionID: PersistentIdentifier? = nil
29:     @State private var sidebarSearch: String = ""
30:     @State private var isLibrarySectionExpanded: Bool = true
31:     @State private var isRecentSectionExpanded: Bool = true
32:     @State private var isLanguagesSectionExpanded: Bool = true
33:     @State private var isAllSnippetsExpanded: Bool = false
34:     @State private var expandedCollections: Set<PersistentIdentifier> = []
35: 
36:     private var collectionNameMatches: [SnippetCollection] {
37:         let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
38:         guard !needle.isEmpty else { return [] }
39:         return collections.filter { $0.name.lowercased().contains(needle) }
40:     }
41: 
42:     private var baseFilteredSnippets: [Snippet] {
43:         snippets.filter { snippet in
44:             if let selectedLanguage, snippet.language != selectedLanguage.rawValue { return false }
45:             if let selectedCollectionID {
46:                 return snippet.collections.contains(where: { $0.persistentModelID == selectedCollectionID })
47:             }
48:             return true
49:         }
50:     }
51: 
52:     private var snippetsInCollectionSearchSection: [Snippet] {
53:         guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
54:         let matchedIDs = Set(collectionNameMatches.map(\.persistentModelID))
55:         return baseFilteredSnippets.filter { snippet in
56:             snippet.collections.contains(where: { matchedIDs.contains($0.persistentModelID) })
57:         }
58:     }
59: 
60:     private var snippetsInContentSearchSection: [Snippet] {
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
