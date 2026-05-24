Created At: 2026-05-24T14:42:14Z
Completed At: 2026-05-24T14:42:15Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1827
Total Bytes: 79684
Showing lines 550 to 600
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
550: 
551: 
552:     private var frequentlyUsedSection: some View {
553:         DisclosureGroup(isExpanded: $isFrequentlyUsedSectionExpanded) {
554:             VStack(alignment: .leading, spacing: 4) {
555:                 ForEach(frequentlyUsedSnippets) { snippet in
556:                     frequentlyUsedRow(for: snippet)
557:                 }
558:             }
559:             .padding(.top, 4)
560:         } label: {
561:             Text("frequently used")
562:                 .font(Mono.font(size: 11, weight: .semibold))
563:                 .foregroundStyle(theme.textMuted)
564:         }
565:     }
566: 
567:     private var languagesSection: some View {
568:         DisclosureGroup(isExpanded: $isLanguagesSectionExpanded) {
569:             VStack(alignment: .leading, spacing: 4) {
570:                 HStack(spacing: 8) {
571:                     Text("languages")
572:                         .font(Mono.font(size: 11, weight: .semibold))
573:                         .foregroundStyle(theme.textMuted)
574:                     Text("\(sidebarFilteredLanguages.count)")
575:                         .font(Mono.font(size: 10, weight: .medium))
576:                         .foregroundStyle(theme.textFaint)
577:                 }
578:                 .padding(.horizontal, 10)
579:                 .padding(.bottom, 2)
580: 
581:                 ForEach(sidebarFilteredLanguages) { language in
582:                     let accent = Color(hex: language.accentHex) ?? theme.accent
583:                     sidebarRow(
584:                         icon: language.symbolName,
585:                         title: language.rawValue.lowercased(),
586:                         count: snippets.filter { $0.language == language.rawValue }.count,
587:                         isActive: selectedLanguages.contains(language) && selectedSnippetID == nil,
588:                         accent: accent
589:                     ) {
590:                         if selectedLanguages.contains(language) {
591:                             selectedLanguages.remove(language)
592:                         } else {
593:                             selectedLanguages.insert(language)
594:                         }
595:                         selectedSnippetID = nil
596:                         selectedCollectionID = nil
597:                     }
598:                 }
599:                 if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
600:                     Text("no matches")
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
