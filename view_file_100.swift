Created At: 2026-05-24T14:34:56Z
Completed At: 2026-05-24T14:34:56Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79475
Showing lines 1326 to 1342
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
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
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
