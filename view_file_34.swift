Created At: 2026-05-24T14:22:41Z
Completed At: 2026-05-24T14:22:41Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79511
Showing lines 1250 to 1330
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1250:             if !frequentlyUsedSnippets.isEmpty {
1251:                 Section("Frequently Used", isExpanded: $isFrequentlyUsedSectionExpanded) {
1252:                     ForEach(frequentlyUsedSnippets) { snippet in
1253:                         let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
1254:                         let accent = Color(hex: language.accentHex) ?? .accentColor
1255:                         let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .frequentlyUsed
1256:                         Label {
1257:                             Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
1258:                                 .foregroundStyle(isActive ? .white : .primary)
1259:                                 .lineLimit(1)
1260:                                 .truncationMode(.tail)
1261:                                 .instantSidebarSelectionStyle()
1262:                         } icon: {
1263:                             Circle()
1264:                                 .fill(isActive ? .white : accent)
1265:                                 .frame(width: 8, height: 8)
1266:                                 .instantSidebarSelectionStyle()
1267:                         }
1268:                         .tag(Selection.snippet(snippet.persistentModelID, .frequentlyUsed))
1269:                         .contextMenu {
1270:                             Button { onEditSnippet(snippet) } label: {
1271:                                 Label("Edit snippet", systemImage: "pencil")
1272:   
<truncated 1443 bytes>
accentColor
1297:                         let isActive = selectedLanguages.contains(language) && selectedSnippetID == nil && selectedCollectionID == nil && sidebarSelectionContext != .trash
1298:                         Label {
1299:                             HStack {
1300:                                 Text(language.rawValue)
1301:                                     .foregroundStyle(isActive ? .white : .primary)
1302:                                     .instantSidebarSelectionStyle()
1303:                                 Spacer()
1304:                                 Text("\(count)")
1305:                                     .foregroundStyle(isActive ? .white.opacity(0.72) : .secondary)
1306:                                     .monospacedDigit()
1307:                                     .instantSidebarSelectionStyle()
1308:                             }
1309:                         } icon: {
1310:                             Image(systemName: language.symbolName)
1311:                                 .symbolRenderingMode(.hierarchical)
1312:                                 .foregroundStyle(isActive ? .white : accent)
1313:                                 .instantSidebarSelectionStyle()
1314:                         }
1315:                         .tag(Selection.language(language.rawValue))
1316:                     }
1317: 
1318:                     if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
1319:                         Text("No matches")
1320:                             .foregroundStyle(.secondary)
1321:                             .font(.callout)
1322:                     }
1323:                 }
1324:             }
1325: 
1326:             Section {
1327:                 Label {
1328:                     HStack {
1329:                         Text("Trash")
1330:                         Spacer()
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
