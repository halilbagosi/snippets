---
type: community
cohesion: 0.20
members: 14
---

# Bulk Delete Confirmation Model

**Cohesion:** 0.20 - loosely connected
**Members:** 14 nodes

## Members
- [[.decide()]] - code - Sources/Snippets/Features/Gallery/SnippetGalleryViewModel.swift
- [[.test_decide_collectionsOnlyWithFixedBehaviorAndConfirmationOff_deletesImmediately()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[.test_decide_collectionsWithAskBehavior_asksEvenWhenSnippetConfirmationIsOff()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[.test_decide_collectionsWithAskBehavior_asksForCollectionBehaviorOnce()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[.test_decide_snippetsAndCollectionsWithFixedBehavior_confirmsOnceUsingThatBehavior()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[.test_decide_snippetsOnlyWithConfirmationOff_deletesImmediately()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[.test_decide_snippetsOnlyWithConfirmationOn_confirmsOnce()]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[BulkDeleteConfirmation]] - code - Sources/Snippets/Features/Gallery/SnippetGalleryViewModel.swift
- [[Equatable]] - code
- [[Int_4]] - code
- [[SnippetGalleryViewModelTests]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[askCollectionBehavior]] - code - Sources/Snippets/Features/Gallery/SnippetGalleryViewModel.swift
- [[confirmOnce]] - code - Sources/Snippets/Features/Gallery/SnippetGalleryViewModel.swift
- [[deleteImmediately]] - code - Sources/Snippets/Features/Gallery/SnippetGalleryViewModel.swift

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Bulk_Delete_Confirmation_Model
SORT file.name ASC
```

## Connections to other communities
- 6 edges to [[_COMMUNITY_Snippet Gallery View Model]]
- 2 edges to [[_COMMUNITY_Appearance Settings (NSAppearance)]]
- 1 edge to [[_COMMUNITY_App Module Imports & DS Radius]]
- 1 edge to [[_COMMUNITY_ContentView Root Coordination]]
- 1 edge to [[_COMMUNITY_SnippetGalleryView Selection UI]]
- 1 edge to [[_COMMUNITY_Snippet Editor View Model]]

## Top bridge nodes
- [[SnippetGalleryViewModelTests]] - degree 12, connects to 4 communities
- [[BulkDeleteConfirmation]] - degree 8, connects to 3 communities
- [[.decide()]] - degree 11, connects to 2 communities