---
type: community
cohesion: 0.11
members: 31
---

# Snippet Editor View Model

**Cohesion:** 0.11 - loosely connected
**Members:** 31 nodes

## Members
- [[.detect()]] - code - Sources/Snippets/Services/LanguageDetector.swift
- [[.fileExtension()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.hasUnsavedData()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.headerFilename()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.load()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.resetManualLanguage()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.save()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.selectManualLanguage()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.selectedCollections()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.test_canSave_whenRequiredFieldsAreMissing_returnsFalse()]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[.test_headerFilename_whenTitleAndLanguageAreSet_returnsSanitizedFilename()]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[.test_load_whenEditingSnippet_populatesFormState()]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[.test_toggleCollection_whenCollectionIsUnselected_selectsIt()]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[.toggleCollection()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.updateCodeCaches()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.updateDetectedLanguage()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[.updateTitleCaches()]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[Bool_6]] - code
- [[Int_2]] - code
- [[ModelContext]] - code
- [[PersistentIdentifier_2]] - code
- [[Set_2]] - code
- [[SnippetCollection_2]] - code
- [[SnippetEditorMode]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[SnippetEditorViewModel]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[SnippetEditorViewModelTests]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[String_7]] - code
- [[Void_5]] - code
- [[XCTestCase]] - code
- [[create]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift
- [[edit]] - code - Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Snippet_Editor_View_Model
SORT file.name ASC
```

## Connections to other communities
- 7 edges to [[_COMMUNITY_Language Detector Rules]]
- 5 edges to [[_COMMUNITY_Snippet Gallery View Model]]
- 5 edges to [[_COMMUNITY_App Environment & Media Protocol]]
- 5 edges to [[_COMMUNITY_Appearance Settings (NSAppearance)]]
- 3 edges to [[_COMMUNITY_Snippet Editor Media Fields]]
- 2 edges to [[_COMMUNITY_App Module Imports & DS Radius]]
- 1 edge to [[_COMMUNITY_Bulk Delete Confirmation Model]]
- 1 edge to [[_COMMUNITY_Snippet Query Filter]]

## Top bridge nodes
- [[SnippetEditorViewModel]] - degree 32, connects to 6 communities
- [[XCTestCase]] - degree 6, connects to 3 communities
- [[SnippetEditorMode]] - degree 8, connects to 2 communities
- [[SnippetEditorViewModelTests]] - degree 7, connects to 2 communities
- [[.detect()]] - degree 5, connects to 2 communities