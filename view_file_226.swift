Created At: 2026-05-24T14:51:30Z
Completed At: 2026-05-24T14:51:30Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1861
Total Bytes: 81750
Showing lines 620 to 680
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
620:             .padding(.top, 4)
621:         } label: {
622:             HStack(spacing: 8) {
623:                 Text("languages")
624:                     .font(Mono.font(size: 11, weight: .semibold))
625:                     .foregroundStyle(theme.textMuted)
626:                 Text("\(sidebarFilteredLanguages.count)")
627:                     .font(Mono.font(size: 10, weight: .medium))
628:                     .foregroundStyle(theme.textFaint)
629:             }
630:         }
631:     }
632: 
633:     @ViewBuilder
634:     private func sidebarRow(
635:         icon: String,
636:         title: String,
637:         count: Int,
638:         isActive: Bool,
639:         accent: Color,
640:         action: @escaping () -> Void
641:     ) -> some View {
642:         Button(action: action) {
643:             HStack(spacing: 8) {
644:                 Image(systemName: icon)
645:                     .font(Mono.font(size: 11, weight: .semibold))
646:                     .symbolRenderingMode(.hierarchical)
647:                     .frame(width: 14)
648:                     .foregroundStyle(isActive ? .white : accent)
649:                     .animation(nil, value: isActive)
650:                     .instantSidebarSelectionStyle()
651:                 Text(title)
652:                     .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
653:                     .foregroundStyle(isActive ? .white : theme.textMuted)
654:                     .lineLimit(1)
655:                     .animation(nil, value: isActive)
656:                     .instantSidebarSelectionStyle()
657:                 Spacer(minLength: 4)
658:                 Text("\(count)")
659:                     .font(Mono.font(size: 10, weight: .semibold))
660:                     .foregroundStyle(isActive ? .white.opacity(0.72) : theme.textFaint)
661:                     .instantSidebarSelectionStyle()
662:             }
663:             .padding(.horizontal, 10)
664:             .padding(.vertical, 6)
665:             .background {
666:                 sidebarSelectionBackground(isActive: isActive)
667:             }
668:             .contentShape(Rectangle())
669:         }
670:         .buttonStyle(.plain)
671:     }
672: 
673:     @ViewBuilder
674:     private func sidebarSelectionBackground(isActive: Bool) -> some View {
675:         RoundedRectangle(cornerRadius: 6, style: .continuous)
676:             .fill(isActive ? Color.accentColor : Color.clear)
677:     }
678: 
679:     @ViewBuilder
680:     private func frequentlyUsedRow(for snippet: Snippet) -> some View {
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
