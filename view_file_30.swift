Created At: 2026-05-24T14:22:23Z
Completed At: 2026-05-24T14:22:23Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79456
Showing lines 1185 to 1250
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1185:     var body: some View {
1186:         List(selection: selection) {
1187:             Section("Snippets", isExpanded: $isLibrarySectionExpanded) {
1188:                 DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
1189:                     ForEach(snippets) { snippet in
1190:                         let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
1191:                         let accent = Color(hex: language.accentHex) ?? .accentColor
1192:                         let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .allSnippets
1193:                         Label {
1194:                             Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
1195:                                 .foregroundStyle(isActive ? .white : .primary)
1196:                                 .lineLimit(1)
1197:                                 .truncationMode(.tail)
1198:                                 .instantSidebarSelectionStyle()
1199:                         } icon: {
1200:                             Circle()
1201:                                 .fill(isActive ? .white : accent)
1202:                                 .frame(width: 8, height: 8)
1203:                                 .instantSidebarSelectionStyle()
1204:                         }
1205:                         .tag(Selection.snippet(snippet.persistentModelID, .allSnippets))
1206:                         .draggable(String(snippet.persistentModelID.hashValue))
1207:                         .contextMenu {
1208:                   
<truncated 791 bytes>
              Menu("Copy to") {
1217:                                 ForEach(collections) { collection in
1218:                                     Button { onCopySnippetToCollection(snippet, collection) } label: { Label(collection.name, systemImage: collection.displayIconName) }
1219:                                 }
1220:                             }
1221:                         }
1222:                     }
1223:                 } label: {
1224:                     let isActive = selection.wrappedValue == .all
1225:                     Label {
1226:                         HStack {
1227:                             Text("All snippets")
1228:                                 .foregroundStyle(isActive ? .white : .primary)
1229:                                 .instantSidebarSelectionStyle()
1230:                             Spacer()
1231:                             Text("\(snippets.count)")
1232:                                 .foregroundStyle(isActive ? .white.opacity(0.72) : .secondary)
1233:                                 .monospacedDigit()
1234:                                 .instantSidebarSelectionStyle()
1235:                         }
1236:                     } icon: {
1237:                         Image(systemName: "square.grid.2x2")
1238:                             .foregroundStyle(isActive ? .white : .primary)
1239:                             .instantSidebarSelectionStyle()
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
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
