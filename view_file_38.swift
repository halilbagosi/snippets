Created At: 2026-05-24T14:22:59Z
Completed At: 2026-05-24T14:22:59Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79566
Showing lines 1360 to 1440
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1360:             .padding(12)
1361:         }
1362:     }
1363: 
1364:     @ViewBuilder
1365:     private func modernCollectionTree(for collection: SnippetCollection) -> some View {
1366:         let isExpanded = Binding(
1367:             get: { expandedCollections.contains(collection.persistentModelID) },
1368:             set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
1369:         )
1370:         DisclosureGroup(isExpanded: isExpanded) {
1371:             ForEach(collection.children) { child in
1372:                 AnyView(modernCollectionTree(for: child))
1373:             }
1374:             ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
1375:                 let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
1376:                 let accent = Color(hex: language.accentHex) ?? .accentColor
1377:                 let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
1378:                 Label {
1379:                     Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
1380:                         .foregroundStyle(isActive ? .white : .primary)
1381:                         .lineLimit(1)
1382:                         .truncationMode(.tail)
1383:                         .instantSidebarSelectionStyle()
1384:                 } icon: {
1385:                     Circle()
1386:                         .fill(isActive ? .white : accen
<truncated 1362 bytes>
                       }
1405:                     }
1406:                 }
1407:             }
1408:         } label: {
1409:             let isActive = selectedCollectionID == collection.persistentModelID && selectedSnippetID == nil
1410:             Label {
1411:                 HStack {
1412:                     Text(collection.name)
1413:                         .foregroundStyle(isActive ? .white : .primary)
1414:                         .instantSidebarSelectionStyle()
1415:                     Spacer()
1416:                     Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
1417:                         .foregroundStyle(isActive ? .white.opacity(0.72) : .secondary)
1418:                         .monospacedDigit()
1419:                         .instantSidebarSelectionStyle()
1420:                 }
1421:             } icon: {
1422:                 Image(systemName: collection.displayIconName)
1423:                     .symbolRenderingMode(.hierarchical)
1424:                     .foregroundStyle(isActive ? .white : collection.displayColor)
1425:                     .instantSidebarSelectionStyle()
1426:             }
1427:         }
1428:         .tag(Selection.collection(collection.persistentModelID))
1429:         .contextMenu {
1430:             Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
1431:             Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
1432:         }
1433:         .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, collection) }
1434:     }
1435: }
1436: 
1437: private extension View {
1438:     func instantSidebarSelectionStyle() -> some View {
1439:         transaction { transaction in
1440:             transaction.animation = nil
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
