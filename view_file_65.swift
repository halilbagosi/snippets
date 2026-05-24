Created At: 2026-05-24T14:29:14Z
Completed At: 2026-05-24T14:29:14Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79621
Showing lines 1325 to 1362
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1325: 
1326:             Section {
1327:                 Label {
1328:                     HStack {
1329:                         Text("Trash")
1330:                         Spacer()
1331:                         Text("\(trashedSnippetsCount)")
1332:                             .foregroundStyle(.secondary)
1333:                             .monospacedDigit()
1334:                     }
1335:                 } icon: {
1336:                     Image(systemName: "trash")
1337:                 }
1338:                 .tag(Selection.trash)
1339:                 .foregroundStyle(.red)
1340:             }
1341:         }
1342:         .listStyle(.sidebar)
1343:         .scrollContentBackground(.hidden)
1344:         .searchable(
1345:             text: $sidebarSearch,
1346:             placement: .sidebar,
1347:             prompt: Text("Filter languages")
1348:         )
1349:         .safeAreaInset(edge: .bottom, spacing: 0) {
1350:             Button(action: onNew) {
1351:                 Label("New Collection", systemImage: "plus")
1352:                     .frame(maxWidth: .infinity)
1353:                     .padding(.vertical, 7)
1354:             }
1355:             .buttonStyle(.borderedProminent)
1356:             .tint(theme.accent)
1357:             .controlSize(.large)
1358:             .clipShape(Capsule(style: .continuous))
1359:             .keyboardShortcut("n", modifiers: [.command, .shift])
1360:             .padding(12)
1361:         }
1362:     }
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
