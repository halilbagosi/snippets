Created At: 2026-05-24T14:41:44Z
Completed At: 2026-05-24T14:41:45Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1827
Total Bytes: 79684
Showing lines 1290 to 1330
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1290: 
1291: 
1292:             if !availableLanguages.isEmpty {
1293:                 Section("Languages", isExpanded: $isLanguagesSectionExpanded) {
1294:                     ForEach(sidebarFilteredLanguages) { language in
1295:                         let count = snippets.filter { $0.language == language.rawValue }.count
1296:                         let accent = Color(hex: language.accentHex) ?? .accentColor
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
1327:                 let isActive = sidebarSelectionContext == .trash
1328:                 Label {
1329:                     HStack {
1330:                         Text("Trash")
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
