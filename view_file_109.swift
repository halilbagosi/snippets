Created At: 2026-05-24T14:36:02Z
Completed At: 2026-05-24T14:36:02Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1827
Total Bytes: 79728
Showing lines 1240 to 1270
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1240:                     }
1241:                 }
1242:                 .tag(Selection.all)
1243:                 .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }
1244: 
1245:                 ForEach(topLevelCollections) { collection in
1246:                     modernCollectionTree(for: collection)
1247:                 }
1248:             }
1249: 
1250:             if !frequentlyUsedSnippets.isEmpty {
1251:                 Section("Frequently Used", isExpanded: $isFrequentlyUsedSectionExpanded) {
1252:                     ForEach(frequentlyUsedSnippets) { snippet in
1253:                         let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
1254:                         let accent = Color(hex: language.accentHex) ?? .accentColor
1255:                         let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .frequentlyUsed
1256:                         Label {
1257:                             Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
1258:                                 .foregroundStyle(isActive ? Color.accentColor : .primary)
1259:                                 .lineLimit(1)
1260:                                 .truncationMode(.tail)
1261:                                 .instantSidebarSelectionStyle()
1262:                         } icon: {
1263:                             Circle()
1264:                                 .fill(isActive ? Color.accentColor : accent)
1265:                                 .frame(width: 8, height: 8)
1266:                                 .instantSidebarSelectionStyle()
1267:                         }
1268:                         .tag(Selection.snippet(snippet.persistentModelID, .frequentlyUsed))
1269:                         .contextMenu {
1270:                             Button { onEditSnippet(snippet) } label: {
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
