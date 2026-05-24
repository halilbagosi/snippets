Created At: 2026-05-24T14:29:58Z
Completed At: 2026-05-24T14:29:58Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79497
Showing lines 1000 to 1030
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
1000:     @ViewBuilder
1001:     private func sidebarSnippetRow(for snippet: Snippet, context: SidebarSelectionContext) -> some View {
1002:         let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
1003:         let accent = Color(hex: language.accentHex) ?? theme.accent
1004:         let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
1005:         Button {
1006:             selectedSnippetID = snippet.persistentModelID
1007:             sidebarSelectionContext = context
1008:         } label: {
1009:             HStack(spacing: 8) {
1010:                 Circle()
1011:                     .fill(isActive ? Color.accentColor : accent)
1012:                     .frame(width: 6, height: 6)
1013:                     .instantSidebarSelectionStyle()
1014:                 Text(snippet.title.isEmpty ? "untitled" : snippet.title)
1015:                     .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
1016:                     .foregroundStyle(isActive ? Color.accentColor : theme.textMuted)
1017:                     .lineLimit(1)
1018:                     .truncationMode(.tail)
1019:                     .instantSidebarSelectionStyle()
1020:                 Spacer(minLength: 4)
1021:             }
1022:             .padding(.horizontal, 10)
1023:             .padding(.vertical, 5)
1024:             .background {
1025:                 sidebarSelectionBackground(isActive: isActive)
1026:             }
1027:             .contentShape(Rectangle())
1028:         }
1029:         .buttonStyle(.plain)
1030:         .draggable(String(snippet.persistentModelID.hashValue))
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
