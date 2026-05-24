Created At: 2026-05-24T14:51:37Z
Completed At: 2026-05-24T14:51:37Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1861
Total Bytes: 81750
Showing lines 1 to 25
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1: import SwiftUI
2: import SwiftData
3: 
4: struct ContentView: View {
5:     @Environment(\.modelContext) private var modelContext
6:     @Environment(\.colorScheme) private var colorScheme
7:     @Environment(AppEnvironment.self) private var appEnvironment
8: 
9:     @Query(filter: #Predicate<Snippet> { $0.deletedAt == nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
10:     private var snippets: [Snippet]
11:     @Query(filter: #Predicate<Snippet> { $0.deletedAt != nil }, sort: [SortDescriptor(\Snippet.deletedAt, order: .reverse)])
12:     private var trashedSnippets: [Snippet]
13:     @Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
14:     private var allSnippets: [Snippet]
15:     @Query(sort: [SortDescriptor(\SnippetCollection.updatedAt, order: .reverse)])
16:     private var collections: [SnippetCollection]
17: 
18:     @State private var selectedLanguages: Set<SupportedLanguage> = []
19:     @State private var selectedSearchCollections: Set<PersistentIdentifier> = []
20:     @State private var searchText: String = ""
21:     @State private var editingSnippet: Snippet? = nil
22:     @State private var isPresentingNew: Bool = false
23:     @State private var isPresentingCollectionEditor: Bool = false
24:     @State private var editingCollection: SnippetCollection? = nil
25:     @State private var collectionDraftName: String = ""
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
