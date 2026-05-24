Created At: 2026-05-24T14:35:40Z
Completed At: 2026-05-24T14:35:40Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1827
Total Bytes: 79728
Showing lines 1185 to 1210
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
1195:                                 .foregroundStyle(isActive ? Color.accentColor : .primary)
1196:                                 .lineLimit(1)
1197:                                 .truncationMode(.tail)
1198:                                 .instantSidebarSelectionStyle()
1199:                         } icon: {
1200:                             Circle()
1201:                                 .fill(isActive ? Color.accentColor : accent)
1202:                                 .frame(width: 8, height: 8)
1203:                                 .instantSidebarSelectionStyle()
1204:                         }
1205:                         .tag(Selection.snippet(snippet.persistentModelID, .allSnippets))
1206:                         .draggable(String(snippet.persistentModelID.hashValue))
1207:                         .contextMenu {
1208:                             Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
1209:                             Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
1210:                             Menu("Move to") {
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
