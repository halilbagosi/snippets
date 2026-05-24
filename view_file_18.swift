Created At: 2026-05-24T14:21:16Z
Completed At: 2026-05-24T14:21:16Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1831
Total Bytes: 79723
Showing lines 853 to 1652
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
853:         }
854:         let restoredSnippet = Snippet(
855:             title: snapshot.title,
856:             snippetDescription: snapshot.snippetDescription,
857:             language: snapshot.language,
858:             code: snapshot.code,
859:             createdAt: snapshot.createdAt,
860:             updatedAt: snapshot.updatedAt,
861:             copyCount: snapshot.copyCount,
862:             mediaItems: restoredMedia,
863:             collections: collections.filter { snapshot.collectionIDs.contains($0.persistentModelID) }
864:         )
865: 
866:         modelContext.insert(restoredSnippet)
867:         try? modelContext.save()
868:         lastDeletedSnippet = nil
869:         return restoredSnippet.persistentModelID
870:     }
871: 
872:     private func performTrashCleanup() {
873:         let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
874:         for snippet in allSnippets {
875:             if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
876:                 for media in snippet.mediaItems {
877:                     MediaManager.deleteFile(for: media)
878:                 }
879:                 modelContext.delete(snippet)
880:             }
881:         }
882:         try? modelContext.save()
883:     }
884: 
885:     private func restore(_ snippet: Snippet) {
886:         snippet.deletedAt = nil
887:         snippet.updatedAt = .now
888:         try? modelContext.save()
889:     }
890: 
891:     private func permanentlyDelete(_ snippet: Snippet) {
892:         for media in sn
<truncated 36451 bytes>
     .textFieldStyle(.plain)
1613:                 .font(.system(size: 24, weight: .bold))
1614:                 .multilineTextAlignment(.center)
1615:                 .foregroundStyle(theme.text)
1616:                 .frame(maxWidth: 340)
1617:         }
1618:         .frame(maxWidth: .infinity)
1619:         .padding(.top, 8)
1620:     }
1621: 
1622:     private var colorStrip: some View {
1623:         HStack(spacing: 16) {
1624:             Image(systemName: "tag")
1625:                 .font(.system(size: 25, weight: .medium))
1626:                 .foregroundStyle(theme.textFaint)
1627:                 .frame(width: 30)
1628: 
1629:             ForEach(palette) { choice in
1630:                 Button {
1631:                     collectionColor = Color(hex: choice.hex) ?? collectionColor
1632:                 } label: {
1633:                     let isSelected = selectedColorHex == choice.hex.lowercased()
1634:                     Circle()
1635:                         .fill(Color(hex: choice.hex) ?? theme.accent)
1636:                         .frame(width: 40, height: 40)
1637:                         .overlay {
1638:                             Circle()
1639:                                 .strokeBorder(isSelected ? .white.opacity(0.92) : .black.opacity(0.14), lineWidth: isSelected ? 3 : 1)
1640:                         }
1641:                         .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 6, x: 0, y: 3)
1642:                 }
1643:                 .buttonStyle(.plain)
1644:                 .help(choice.name)
1645:             }
1646: 
1647:             ZStack {
1648:                 Circle()
1649:                     .fill(collectionColor.opacity(0.34))
1650:                     .frame(width: 40, height: 40)
1651:                     .overlay {
1652:                         Circle()
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
