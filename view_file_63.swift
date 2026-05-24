Created At: 2026-05-24T14:29:10Z
Completed At: 2026-05-24T14:29:10Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79621
Showing lines 387 to 435
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
387:     private var legacySidebar: some View {
388:         ZStack {
389:             theme.canvasDeep.ignoresSafeArea()
390:             DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.72)
391:                 .opacity(0.45)
392:                 .ignoresSafeArea()
393: 
394:             VStack(spacing: 0) {
395:                 sidebarSearchBar
396:                     .padding(.top, 14)
397: 
398:                 ScrollView {
399:                     VStack(alignment: .leading, spacing: 16) {
400:                         newSnippetButton
401: 
402:                         librarySection
403: 
404:                         if !frequentlyUsedSnippets.isEmpty {
405:                             frequentlyUsedSection
406:                         }
407:                         if !availableLanguages.isEmpty {
408:                             languagesSection
409:                         }
410: 
411:                         // Trash entry for legacy sidebar
412:                         sidebarRow(
413:                             icon: "trash",
414:                             title: "trash",
415:                             count: trashedSnippets.count,
416:                             isActive: sidebarSelectionContext == .trash,
417:                             accent: Color.red
418:                         ) {
419:                             sidebarSelectionContext = .trash
420:                             selectedSnippetID = nil
421:                             selectedCollectionID = nil
422:                             selectedLanguages.removeAll()
423:                         }
424: 
425:                         Spacer(minLength: 12)
426:                     }
427:                     .padding(.horizontal, 14)
428:                     .padding(.top, 14)
429:                     .padding(.bottom, 18)
430:                 }
431:                 .scrollIndicators(.hidden)
432: 
433:                 sidebarFooter
434:             }
435:         }
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
