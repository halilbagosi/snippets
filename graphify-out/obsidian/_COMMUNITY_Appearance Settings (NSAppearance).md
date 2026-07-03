---
type: community
cohesion: 0.05
members: 60
---

# Appearance Settings (NSAppearance)

**Cohesion:** 0.05 - loosely connected
**Members:** 60 nodes

## Members
- [[.appearanceName()]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[.appendSubtree()]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[.applyAppAppearance()]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[.assign()]] - code - Sources/Snippets/Intents/UUIDBackfill.swift
- [[.init()_1]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[.init()_13]] - code - Sources/Snippets/Models/Collection.swift
- [[.resolvedColorHex()]] - code - Sources/Snippets/Models/Collection.swift
- [[.rows()]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[.searchRows()]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[.test_appearanceName_darkPreference_isDarkAqua()]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[.test_appearanceName_lightPreference_isAqua()]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[.test_appearanceName_systemPreference_isNilSoAppKitFollowsSystem()]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[.test_appearanceName_unknownPreference_fallsBackToSystem()]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[.test_assign_fillsOnlyNilUUIDs_andReturnsCount()]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[.test_assign_whenNothingMissing_returnsZero()]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[.test_newCollection_hasUUIDByDefault()]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[.test_newSnippet_hasUUIDByDefault()]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[.test_rows_whenChildsParentIsNotInList_treatsChildAsTopLevel()]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[.test_rows_whenCollectionHasChildPresentInList_nestsChildDirectlyAfterParent()]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[.test_rows_whenCollectionsAreFlat_returnsThemAtDepthZeroInInputOrder()]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[.test_searchRows_whenQueryIsBlank_returnsFullHierarchy()]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[.test_searchRows_whenQueryMatchesSubstring_returnsFlatMatchesCaseInsensitively()]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[AppearanceSettings]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[AppearanceSettings.swift]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[AppearanceSettingsTests]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[AppearanceSettingsTests.swift]] - code - Tests/SnippetsTests/AppearanceSettingsTests.swift
- [[Bool_2]] - code
- [[Bool_10]] - code
- [[CollectionMoveRow]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[CollectionMoveTree.swift]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[CollectionMoveTreeTests]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[CollectionMoveTreeTests.swift]] - code - Tests/SnippetsTests/CollectionMoveTreeTests.swift
- [[Color_3]] - code
- [[Date_1]] - code
- [[Int_3]] - code
- [[Int_6]] - code
- [[Int_7]] - code
- [[Key]] - code - Sources/Snippets/App/AppearanceSettings.swift
- [[MoveCollectionTree]] - code - Sources/Snippets/Features/Gallery/CollectionMoveTree.swift
- [[NSAppearance]] - code
- [[PersistentIdentifier_3]] - code
- [[PersistentIdentifier_5]] - code
- [[Set_3]] - code
- [[Set_6]] - code
- [[SnippetCollection_3]] - code
- [[SnippetCollection_7]] - code
- [[SnippetCollection_8]] - code - Sources/Snippets/Models/Collection.swift
- [[SnippetEditorViewModelTests.swift]] - code - Tests/SnippetsTests/SnippetEditorViewModelTests.swift
- [[SnippetGalleryViewModelTests.swift]] - code - Tests/SnippetsTests/SnippetGalleryViewModelTests.swift
- [[SnippetQueryFilterTests.swift]] - code - Tests/SnippetsTests/SnippetQueryFilterTests.swift
- [[Snippets]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[String_2]] - code
- [[String_8]] - code
- [[String_14]] - code
- [[UUID_5]] - code
- [[UUIDBackfill]] - code - Sources/Snippets/Intents/UUIDBackfill.swift
- [[UUIDBackfill.swift]] - code - Sources/Snippets/Intents/UUIDBackfill.swift
- [[UUIDBackfillTests]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[UUIDBackfillTests.swift]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift
- [[XCTest]] - code - Tests/SnippetsTests/UUIDBackfillTests.swift

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Appearance_Settings_NSAppearance
SORT file.name ASC
```

## Connections to other communities
- 7 edges to [[_COMMUNITY_Snippet Gallery View Model]]
- 5 edges to [[_COMMUNITY_App Module Imports & DS Radius]]
- 5 edges to [[_COMMUNITY_Snippet Editor View Model]]
- 3 edges to [[_COMMUNITY_SnippetGalleryView Selection UI]]
- 2 edges to [[_COMMUNITY_Legacy CollectionEditorSheet (root)]]
- 2 edges to [[_COMMUNITY_Clipboard & LanguageBadge]]
- 2 edges to [[_COMMUNITY_AppDelegate & AVPlayer Video]]
- 2 edges to [[_COMMUNITY_Bulk Delete Confirmation Model]]
- 2 edges to [[_COMMUNITY_Sidebar LegacyModern Duality]]
- 1 edge to [[_COMMUNITY_DSColor Design Tokens]]
- 1 edge to [[_COMMUNITY_AppKit TextNSTextStorage Bridging]]
- 1 edge to [[_COMMUNITY_SnippetCollectionEntity App Intent]]
- 1 edge to [[_COMMUNITY_SnippetEntity App Intent]]
- 1 edge to [[_COMMUNITY_Settings About View & Shapes]]
- 1 edge to [[_COMMUNITY_Snippet Query Filter]]

## Top bridge nodes
- [[SnippetCollection_8]] - degree 17, connects to 5 communities
- [[.assign()]] - degree 9, connects to 4 communities
- [[CollectionMoveTreeTests]] - degree 10, connects to 3 communities
- [[AppearanceSettings.swift]] - degree 5, connects to 3 communities
- [[CollectionMoveRow]] - degree 11, connects to 2 communities