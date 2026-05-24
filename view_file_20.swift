Created At: 2026-05-24T14:21:21Z
Completed At: 2026-05-24T14:21:21Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1831
Total Bytes: 79723
Showing lines 621 to 780
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
621:     private func sidebarRow(
622:         icon: String,
623:         title: String,
624:         count: Int,
625:         isActive: Bool,
626:         accent: Color,
627:         action: @escaping () -> Void
628:     ) -> some View {
629:         Button(action: action) {
630:             HStack(spacing: 8) {
631:                 Image(systemName: icon)
632:                     .font(Mono.font(size: 11, weight: .semibold))
633:                     .symbolRenderingMode(.hierarchical)
634:                     .frame(width: 14)
635:                     .foregroundStyle(isActive ? .white : accent)
636:                     .instantSidebarSelectionStyle()
637:                 Text(title)
638:                     .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
639:                     .foregroundStyle(isActive ? .white : theme.textMuted)
640:                     .lineLimit(1)
641:                     .instantSidebarSelectionStyle()
642:                 Spacer(minLength: 4)
643:                 Text("\(count)")
644:                     .font(Mono.font(size: 10, weight: .semibold))
645:                     .foregroundStyle(isActive ? .white.opacity(0.72) : theme.textFaint)
646:                     .instantSidebarSelectionStyle()
647:             }
648:             .padding(.horizontal, 10)
649:             .padding(.vertical, 6)
650:             .background {
651:                 sidebarSelectionBackground(accent: accent, isActive: isActive)
652:             }
653:             .contentShape(Rectangle())
654:         }
655:         .buttonStyle(.pl
<truncated 4288 bytes>
nEditCollection(collection) } label: {
745:                 Label("Edit collection", systemImage: "pencil")
746:             }
747:             Button(role: .destructive) { delete(collection) } label: {
748:                 Label("Delete collection", systemImage: "trash")
749:             }
750:         }
751:     }
752: 
753:     @ViewBuilder
754:     private func legacyCollectionTree(for collection: SnippetCollection) -> some View {
755:         let isExpanded = Binding(
756:             get: { expandedCollections.contains(collection.persistentModelID) },
757:             set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
758:         )
759:         DisclosureGroup(isExpanded: isExpanded) {
760:             VStack(alignment: .leading, spacing: 2) {
761:                 ForEach(collection.children) { child in
762:                     AnyView(legacyCollectionTree(for: child))
763:                 }
764:                 ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
765:                     sidebarSnippetRow(for: snippet, context: .collection(collection.persistentModelID))
766:                 }
767:             }
768:             .padding(.leading, 12)
769:         } label: {
770:             collectionRow(for: collection)
771:                 .dropDestination(for: String.self) { items, _ in
772:                     return handleDrop(items: items, to: collection)
773:                 }
774:         }
775:     }
776: 
777:     private var sidebarFooter: some View {
778:         HStack(spacing: 10) {
779:             footerStat(icon: "doc.text", value: "\(snippets.count)", label: "snips")
780:             footerStat(icon: "chevron.left.forwardslash.chevron.right", value: "\(availableLanguages.count)", label: "langs")
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
