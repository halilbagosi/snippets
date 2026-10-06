# 017 — Snippet import & export (design)

**Status:** implemented, 2026-10-06 · **Branch:** `feature/snippet-import-export` (off `finalizing`)

## Goal

One file format, two jobs:

- **Backup / migration** — export the whole library and restore it, including
  into the sandboxed App Store build, whose container cannot see the
  unsandboxed library in `~/Library/Application Support`.
- **Sharing** — export chosen snippets or a collection and hand the file to
  someone else.

## User-facing behaviour

### Entry points

| Action | Where | Exports |
|---|---|---|
| Export Library… (⇧⌘E) | File menu | every snippet not in Trash |
| Export Collection… | collection context menu (sidebar) | the collection, its subcollections, and their snippets |
| Export… | snippet card context menu | that snippet |
| Export | bulk-selection action bar | the selected snippets |
| Import Snippets… (⇧⌘I) | File menu | — |
| open a `.snippets` file | Finder double-click, AirDrop, drop on Dock icon | — |

Export uses the save panel (default name `Snippets Library.snippets`, the
collection name, or the snippet title). Import uses the open panel filtered to
`.snippets`. All import routes run the same import flow.

### What a file contains

- Snippets: title, description, language, code, createdAt, updatedAt,
  isFavorite, copyCount, saved preview parameter configs (`paramConfigs`,
  including the immutable Default) and `activeParamConfigID`.
- Media attachments, embedded.
- Collections the exported snippets belong to, plus every ancestor up to the
  root so nesting rebuilds; for a collection export, the whole subtree (even
  empty subcollections). Name, colours (light and dark), icon, favourite,
  dates, parent.
- Connections (`dependencies`), in order, **only** where the target snippet is
  also in the export.

Never exported: Trash, preview permissions (run approvals and esm.sh CDN
grants), app settings (including Run Previews Automatically).

### Import conflicts

A snippet conflicts when the library already holds a snippet with the same
`uuid`, including one in Recently Deleted. For each conflict a Finder-style
dialog shows:

> A snippet named “*title*” already exists in your library.
> *(…in Recently Deleted.)* when trashed
>
> [Skip] (default) [Replace] (destructive) [Stop] (Escape) · ☐ Apply to all

The dialog is a sheet on the main gallery window when that window is visible
and has no sheet already; otherwise (no gallery, or one busy with a sheet) it
is an app-modal alert. Skip is the default (Return) because it is the one
choice that cannot lose anything.

- **Skip** leaves the local snippet untouched.
- **Replace** overwrites the local snippet with the imported fields, media,
  collections, connections and configs; clears `deletedAt` if trashed; and
  forgets its preview permissions (`PreviewTrust.forget`) **and those of its
  dependents** — the replaced code runs inside their combined previews.
- **Stop** ends the import. Only snippets *before* the stopped one are
  imported; nothing after it is.
- **Apply to all** reuses the choice for the remaining conflicts without asking.

Collections are matched by `uuid` and silently reused (fields are not
overwritten), so they are never duplicated and never prompt. A matching
collection in Trash is reused and restored from Trash. Imported snippets with a
new `uuid` are added as-is with no preview permissions.

On finish, a toast: “Imported 12 snippets · 3 replaced · 30 skipped” (zero
parts omitted; after Stop: “Import stopped after N snippets · …”). Errors are
shown as an alert and nothing is written. Several files opened at once (a
multi-file Finder open) are queued and imported one after another, each with its
own dialogs and toast.

## File format

UTType `com.halilbagosi.snippets`, extension `.snippets`, conforms to
`public.json`; exported by the app and registered as a Viewer document type so
Finder opens it in Snippets.

```json
{
  "format": "com.halilbagosi.snippets",
  "version": 1,
  "exportedAt": "2026-10-06T10:00:00Z",
  "appVersion": "1.0",
  "collections": [
    { "id": "UUID", "name": "…", "colorHex": "#0A84FF", "colorHexDark": null,
      "iconName": "curlybraces", "parentID": null, "isFavorite": false,
      "createdAt": "…", "updatedAt": "…" }
  ],
  "snippets": [
    { "id": "UUID", "title": "…", "description": "…", "language": "React",
      "code": "…", "createdAt": "…", "updatedAt": "…", "isFavorite": false,
      "copyCount": 0, "collectionIDs": ["UUID"], "dependencyIDs": ["UUID"],
      "paramConfigs": [ /* PreviewParamConfig, existing Codable shape */ ],
      "activeParamConfigID": null,
      "media": [ { "kind": "image", "fileExtension": "png",
                   "addedAt": "…", "data": "<base64>" } ] }
  ]
}
```

Dates are ISO 8601. `id` is the model's `uuid`; a snippet or collection
predating the uuid backfill (`uuid == nil`) is given one at export time and the
model is updated so a re-export is stable.

### Validation (all before any write)

- File larger than 500 MB → “This file is too large to import.” Export applies
  the same cap: an archive over it is not written, and the alert says to export a
  collection or a selection instead.
- Not JSON, or `format` mismatch → “This isn't a Snippets export.”
- `version` > 1 → “This file was made by a newer version of Snippets.”
  `version` < 1 → damaged.
- Duplicate ids within the file → reject the file as damaged.
- Media `kind` must be `image` or `video` and `fileExtension` must be an
  extension of a type in `MediaManager.allowedTypes`; otherwise that
  attachment is dropped (snippet still imported). Imported media is written
  under a fresh `UUID().ext` name, so no path from the file is ever used.
- `parentID`, `collectionIDs`, `dependencyIDs` that reference ids absent from
  the file are dropped (a `parentID` cycle is broken by dropping the parent
  link of the collection that closes it).
- Duplicate `paramConfigs` ids → first kept; only the first `isDefault` config
  stays default. `activeParamConfigID` not among them → nil.
- Attachment `fileExtension` longer than 10 characters → dropped.
- `language` is stored as given (`SupportedLanguage(rawValue:)` already
  normalises casing; unknown values display as Unknown).

## Architecture

New folder `Sources/Snippets/Features/Transfer/` — no SwiftUI in it.

| Unit | Responsibility | Depends on |
|---|---|---|
| `SnippetArchive.swift` | Codable DTOs (`SnippetArchive`, `.Collection`, `.Snippet`, `.Media`), `UTType.snippetsArchive`, `decode(Data) throws -> SnippetArchive` with the validation above, `encode()` | Foundation, UniformTypeIdentifiers |
| `SnippetExporter.swift` | `archive(snippets:, collections:, mediaData:) -> SnippetArchive` — closure computation for collections, dependency filtering, uuid assignment | models, `SnippetArchive` |
| `SnippetImporter.swift` | `apply(_:to:resolve:) async throws -> ImportSummary`, in two phases: an *ask* phase that collects every conflict answer into a plan without touching the context (the dialog is window-modal, so other saves can run meanwhile), then a synchronous *apply* phase (no `await`) that mutates, saves, and rolls back + removes new files on failure | models, `SnippetArchive` |
| `SnippetTransferController.swift` | `@MainActor @Observable` glue: runs panels, reads/writes files, queues incoming URLs, drives the importer, shows the conflict `NSAlert` (suppression checkbox = Apply to all; Skip default, Escape = Stop) and publishes the summary for the toast | the three above, `MediaManager`, `PreviewTrust`, AppKit panels |
| `App/TransferCommands.swift` | File menu items | calls the `SnippetTransferController.shared` singleton directly |

Media I/O goes through two closures (`mediaData(for: MediaItem) -> Data?`,
`writeMedia(Data, ext) throws -> String`) so the exporter and importer stay
testable without touching the real media directory. `MediaManager` gains the
matching two small methods.

Open-from-Finder: `Snippets-Info.plist` gains `UTExportedTypeDeclarations` and
`CFBundleDocumentTypes`; the main window's `.onOpenURL` passes each `.snippets`
URL to `SnippetTransferController.shared.importFile(at:)` (the same entry point
as the File ▸ Import panel), and `.handlesExternalEvents(preferring:allowing:)`
routes it to the existing window. This is deliberately not
`NSApplicationDelegate.application(_:open:)`: implementing that makes a cold
launch from a file skip the main window entirely (found in runtime testing).

The controller reads and decodes the file off the main actor (a `@concurrent`
helper that also balances the security-scoped access), so a large archive does
not freeze the UI; only `SnippetImporter.apply` runs on main. On export the
save panel comes first and the archive is built only after the user confirms.
Attachments whose files can't be read are left out of the archive and counted:
the toast reads “Exported 5 snippets · 2 attachments missing” (singular
“1 attachment missing”; unchanged when none are missing).

App Store entitlements: `com.apple.security.files.user-selected.read-only` →
`read-write` (save panel).

## Testing

`SnippetArchiveTests` (format, validation, sanitising), `SnippetExporterTests`
(selection closure, trash, ordering) and `SnippetImporterTests` (apply rules,
atomicity), all in-memory with closure-backed media:

- round trip into an empty store preserves every exported field, collection
  nesting, dependency order, paramConfigs + active config, media bytes;
- partial export drops out-of-set dependencies, keeps ancestor collections;
  collection export includes empty subcollections;
- conflicts: skip, replace (incl. restoring from Trash and calling
  forgetTrust), stop mid-way keeps earlier results, apply-to-all stops asking;
- collections are reused by uuid, never duplicated;
- rejects: malformed JSON, wrong format, newer version, duplicate ids,
  oversize; drops: bad media kind/extension, dangling references, parent
  cycles, unknown active config;
- trash and preview grants never appear in an export;
- the context has no changes while a conflict is being resolved; Stop imports
  nothing at or after the stopped snippet even with earlier Replace answers;
  replacing forgets trust for dependents too, once each.

Then: full suite in Debug and AppStore (`ENABLE_TESTABILITY=YES`), and a
runtime pass in the sandboxed build — export the unsandboxed library from the
Debug build, import into the App Store build's empty container, re-import to
exercise the conflict dialog.

## Out of scope

Keep Both (import as copies), iCloud sync, exporting app settings, merging
collection fields on conflict, streaming very large media.
