Created At: 2026-05-24T14:29:07Z
Completed At: 2026-05-24T14:29:07Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79621
Showing lines 621 to 665
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
635:                     .foregroundStyle(isActive ? Color.accentColor : accent)
636:                     .instantSidebarSelectionStyle()
637:                 Text(title)
638:                     .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
639:                     .foregroundStyle(isActive ? Color.accentColor : theme.textMuted)
640:                     .lineLimit(1)
641:                     .instantSidebarSelectionStyle()
642:                 Spacer(minLength: 4)
643:                 Text("\(count)")
644:                     .font(Mono.font(size: 10, weight: .semibold))
645:                     .foregroundStyle(isActive ? Color.accentColor.opacity(0.72) : theme.textFaint)
646:                     .instantSidebarSelectionStyle()
647:             }
648:             .padding(.horizontal, 10)
649:             .padding(.vertical, 6)
650:             .background {
651:                 sidebarSelectionBackground(isActive: isActive)
652:             }
653:             .contentShape(Rectangle())
654:         }
655:         .buttonStyle(.plain)
656:     }
657: 
658:     @ViewBuilder
659:     private func sidebarSelectionBackground(isActive: Bool) -> some View {
660:         RoundedRectangle(cornerRadius: 6, style: .continuous)
661:             .fill(isActive ? Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.15) : Color.clear)
662:     }
663: 
664:     @ViewBuilder
665:     private func frequentlyUsedRow(for snippet: Snippet) -> some View {
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
