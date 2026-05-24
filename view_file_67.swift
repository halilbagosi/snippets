Created At: 2026-05-24T14:29:22Z
Completed At: 2026-05-24T14:29:22Z
File Path: `file:///Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift`
Total Lines: 1822
Total Bytes: 79621
Showing lines 175 to 225
The following code has been modified to include a line number before every line, in the format: <line_number>: <original_line>. Please note that any changes targeting the original code should remove the line number, colon, and leading space.
175:         }
176:         return colors
177:     }
178: 
179:     var body: some View {
180:         NavigationSplitView {
181:             sidebar
182:                 .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
183:         } detail: {
184:             ZStack {
185:                 Group {
186:                     DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78)
187:                         .ignoresSafeArea()
188:                 }
189: 
190:                 VStack(spacing: 0) {
191:                         SnippetGalleryView(
192:                             snippets: sidebarSelectionContext == .trash ? (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trashedSnippets : []) : gallerySnippets,
193:                             collectionMatchSnippets: sidebarSelectionContext == .trash ? [] : snippetsInCollectionSearchSection,
194:                             contentMatchSnippets: sidebarSelectionContext == .trash ? (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : trashedSnippets.filter { snippet in
195:                                 let needle = searchText.lowercased()
196:                                 return snippet.title.lowercased().contains(needle) || snippet.snippetDescription.lowercased().contains(needle) || snippet.code.lowercased().contains(needle)
197:                             }) : snippetsInContentSearchSection,
198:                             searchQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
199:                          
<truncated 46 bytes>
               selectedLanguages: $selectedLanguages,
201:                             selectedSearchCollections: $selectedSearchCollections,
202:                             availableLanguages: sidebarSelectionContext == .trash ? [] : availableLanguages,
203:                             availableCollections: collections,
204:                             onSelect: { snippet in
205:                                 withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
206:                                     selectedSnippetID = snippet.persistentModelID
207:                                     if sidebarSelectionContext != .trash {
208:                                         if let colID = selectedCollectionID {
209:                                             sidebarSelectionContext = .collection(colID)
210:                                         } else {
211:                                             sidebarSelectionContext = .allSnippets
212:                                         }
213:                                     }
214:                                 }
215:                             },
216:                             onNew: { isPresentingNew = true },
217:                             onDelete: { snippet in delete(snippet) },
218:                             onUndoDelete: { restoreLastDeletedSnippet() },
219:                             isTrashMode: sidebarSelectionContext == .trash,
220:                             onRestore: { snippet in restore(snippet) },
221:                             onPermanentDelete: { snippet in permanentlyDelete(snippet) }
222:                         )
223:                         .blur(radius: selectedSnippet == nil ? 0 : 2)
224:                         .saturation(selectedSnippet == nil ? 1.0 : 0.95)
225:                         .allowsHitTesting(selectedSnippet == nil)
The above content does NOT show the entire file contents. If you need to view any lines of the file which were not shown to complete your task, call this tool again to view those lines.
