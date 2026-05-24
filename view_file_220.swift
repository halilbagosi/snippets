Created At: 2026-05-24T14:51:11Z
Completed At: 2026-05-24T14:51:11Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1861
Total Bytes: 81750
Showing lines 50 to 75
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
50:         let fileName: String
51:         let kind: MediaKind
52:         let addedAt: Date
53:     }
54: 
55:     private struct DeletedSnippetSnapshot {
56:         let id: PersistentIdentifier
57:         let title: String
58:         let snippetDescription: String
59:         let language: String
60:         let code: String
61:         let createdAt: Date
62:         let updatedAt: Date
63:         let copyCount: Int
64:         let mediaItems: [DeletedMediaSnapshot]
65:         let collectionIDs: [PersistentIdentifier]
66:     }
67: 
68:     private var topLevelCollections: [SnippetCollection] {
69:         collections.filter { $0.parent == nil }
70:     }
71: 
72:     private var collectionNameMatches: [SnippetCollection] {
73:         let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
74:         guard !needle.isEmpty else { return [] }
75:         return collections.filter { $0.name.lowercased().contains(needle) }
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
