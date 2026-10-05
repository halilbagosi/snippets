# Implementation Plans

Two audit rounds live here.

**Round 1** — improve skill, 2026-07-15, at commit `79537db3` (branch
`snippet-live-previews-connections`). Plans 001–010, all **DONE**.

**Round 2** — improve skill, 2026-07-31, at commit `08bb49c3` (branch `dev`).
Plans 011–016, scoped to code landed since round 1: menu-bar quick copy and
clipboard capture (2026-07-28/29), preview trust and security hardening
(2026-07-28), and the gaps round 1 deliberately left open. **The working tree
had two uncommitted files when these were written** (`SnippetGalleryView.swift`,
`GallerySection.swift` — in-progress gallery animation work, excluded from
findings); run each plan's drift check before executing.

Execute in the order below unless dependencies say otherwise. Each executor:
read the plan fully before starting, honor its STOP conditions, and update your
row when done.

## Build and test commands

**Corrected 2026-07-31.** This file previously told executors to use
`swift build` / `swift test --build-path …`. Those commands do not work in this
repo and never should have been published here — there is no `Package.swift`,
and `Snippets.xcodeproj` is the only build system. Round-1 plan files
(001–010) still carry the wrong commands in their own tables; they are all DONE
and are left as an archive rather than rewritten. **If you are executing an old
plan, use the commands below, not the ones in the plan file.**

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Build
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build

# Test — 389 cases; hosted by the app, so a run briefly launches Snippets.app
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```

New or moved files must be registered in `Snippets.xcodeproj/project.pbxproj`
(under `Sources/` for the `Snippets` target, `Tests/SnippetsTests/` for the
`SnippetsTests` target). A file that only exists on disk is silently not
compiled. See the repo `CLAUDE.md`.

## Execution order & status

### Round 2 — 2026-07-31, commit `08bb49c3`

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 011 | Deliver quick-copy handoffs when the main window is closed | P1 | S | — | DONE |
| 012 | Auto-dismiss the quick-copy panel when the clipboard opened it | P1 | S | 011 (same file) | DONE |
| 013 | Determine whether macOS gates ClipboardMonitor's pasteboard reads | P1 | M | — | DONE (3A — no alert observed on macOS 27.0 / 26A5388g) |
| 014 | Route every copy path through `SnippetStore.recordCopy` | P2 | S | — | DONE |
| 015 | Document the menu bar, quick copy, capture and previews in the README | P2 | S | 013 (partial — see notes) | DONE |
| 016 | Forget a snippet's preview grants when it is hard-deleted | P3 | S | — | DONE |

### Round 1 — 2026-07-15, commit `79537db3`

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001 | Fix README requirements; add repo CLAUDE.md | P1 | S | — | DONE |
| 002 | Trash/delete integrity (purge collections, honor permanent, surface saves) | P1 | M | — | DONE |
| 003 | Web preview CSP + navigation lockdown | P1 | M | — | DONE |
| 004 | Crash-safe Swift-preview dylib cache | P2 | S | — | DONE |
| 005 | Design doc: sandbox/contain Swift-preview execution | P2 | L (design M) | — | DONE (design at `005-design-output.md`; spike skipped, rationale in doc) |
| 006 | Characterization tests for App Intents | P1 | M | — | DONE |
| 007 | CI workflow (swift test + web build) | P2 | M | 001, 006 | DONE (now also runs the vendored-runtime checksum job) |
| 008 | Delete dead DesignSystem components | P2 | S | — | DONE |
| 009 | Incremental web-preview updates | P3 | M | 003 | DONE (source fast path covers JS/TS/React; HTML/CSS/GLSL force full reload) |
| 010 | Memoize gallery filtering/search | P3 | M | 002 (same file) | DONE (isFavorite + membership hashed directly — toggles skip updatedAt) |

Status values: TODO | IN PROGRESS | DONE | BLOCKED (with one-line reason) | REJECTED (with one-line rationale)

## Dependency notes

- **011 before 012.** Both edit `Sources/Snippets/Services/MenuBarController.swift`,
  in different functions (`MainWindowOpener.activate` / `makeRoot` versus
  `showPanel` / `hidePanel` / the window-delegate callbacks). Landing 011 first
  avoids churn on line anchors, and 012's step-4 runtime check for "Save as
  snippet" is only meaningful once 011's handoff works.
- **013 before 015's clipboard paragraph.** If macOS turns out to gate the
  pasteboard read, the capture feature's user-facing description changes, and
  documenting the current behaviour first would just mean rewriting it. The rest
  of 015 (menu bar, quick copy, previews, project structure) has no such
  dependency and can proceed in parallel.
- **014 and 016 are independent** of everything else and of each other. Either
  can be picked up by an executor working in parallel.
- 016 relates to `005-design-output.md`: a grant list nobody prunes becomes
  load-bearing the moment snippet import/sharing ships, which is what 005 gates.

## Direction findings (options recorded, no plans written)

- **A global hotkey for the quick-copy panel.** The panel is fully
  keyboard-driven (arrows, Return, ⌘Return, ⌘1–4, Escape) but only reachable by
  *clicking* the status item, so every use starts with a mouse trip to the menu
  bar. `MenuBarController.togglePanel()` is already the single entry point, so
  this is a registration problem rather than an architectural one. Costs: a
  `CGEvent` tap (heavier, more permission surface) or
  `NSEvent.addGlobalMonitorForEvents`, plus a shortcut-recorder UI in Settings.
  Note for whoever builds it: a hotkey-opened panel wants plan 012's *click*
  lifecycle (`openedByCapture: false`, key focus, no timeout), not the capture one.
- **A short capture history instead of a single moment.** `pendingCapture` holds
  at most one candidate and expires after six seconds; copy two things quickly
  and the first is gone. A three-or-four-entry ring buffer would make the feature
  forgiving. It changes the privacy story though — a transient in-memory value
  becomes a small retained buffer of copied content — so it is a decision, not a
  tweak, and it would change the meaning of plan 012's timer.
- **Export/import** (carried from round 1): full CRUD + intents but no
  backup/share path for a local-only store; `SnippetLinker.resolve` already
  computes the dependency closure an export would serialize. The import side
  stays blocked on 005's trust-model decision, and that gate is still right.
- **Render previews to image** (carried from round 1): three preview engines
  with no output consumer beyond the screen; per-engine snapshot is cheap
  (WKWebView `takeSnapshot`, Metal readback, `ImageRenderer`).
- **Token codegen for the React port** (carried from round 1): generate Swift +
  TS tokens from one source, or add a parity test, to enforce the "Swift is
  source of truth" claim in `web/design-system/README.md`.

## Findings considered and rejected (do not re-audit)

### From round 2 (2026-07-31)

- Anything already settled in `Docs/security-overview.md` (2026-07-28) — full-document
  CSP, the esm.sh grant model, preview consent gating, the dylib cache HMAC,
  media filename traversal, Metal param buffer sizing, vendored-runtime
  provenance. That document is the authority; its §4 residual risks are
  documented decisions, not open findings. The one exception is its §4 item 6,
  which is now plan 016.
- The two uncommitted gallery files (`SnippetGalleryView.swift`,
  `GallerySection.swift`): in-progress animation work, read and found careful.
  Not a finding; re-read after it lands if you want it audited.
- `ClipboardMonitor`'s per-second `Timer` allocating a `Task` on every tick:
  negligible at 1 Hz, and the timer carries a tolerance so the OS can coalesce
  it. Not worth the churn.
- Double `model.reload()` on panel open (`MenuBarController.showPanel` and
  `QuickCopyPanel.onAppear` both call it): a redundant fetch, but the panel's
  result set is small and correctness depends on the reload being unconditional.
  Leave it.
- `QuickCopyViewModelTests` having only 2 cases: the panel's real logic lives in
  the pure types (`QuickCopyResults`, `QuickCopySelection`, `ClipboardCapture`,
  `CodeShapeHeuristics`), which are well covered. Not a coverage gap.

### From round 1 (2026-07-15)

- Custom `isDeleted` shadowing `PersistentModel.isDeleted` (models + ~10 call
  sites): real but low-impact rename; do opportunistically during a future
  god-file refactor.
- God-file breakup (`SnippetGalleryView` / `ContentView` / `SnippetDetailView`):
  deferred. **Round-2 note:** the trend is worth watching — `SnippetGalleryView`
  went 1521 → 1896 lines and `ContentView` 1453 → 1701 between the two audits.
  Still deferred, but a third round should probably stop deferring it.
- `SnippetEntity` fabricated UUID + un-backfilled collection filter in
  `FindSnippetsIntent`: latent; characterized (not fixed) by plan 006's tests.
- `MediaManager.resolvedURL` path-traversal guard: **superseded** — fixed
  2026-07-28, see `Docs/security-overview.md` §2.6.
- `stripModuleSyntax` blind string replacement in `WebPreviewHTMLBuilder`: real
  edge case, low frequency; proper fix needs tokenizing — revisit if users
  report corrupted previews.
- Metal shader runtime compilation: reviewed, low risk by design (GPU driver
  surface, no filesystem/network sink); optional compile watchdog only.
- Vendored React/Babel provenance manifest: **superseded** — done 2026-07-28,
  see `Docs/security-overview.md` §2.5 and the `vendored-runtimes` CI job.
- Dual build system consolidation: **resolved** — there is no `Package.swift`
  any more; `Snippets.xcodeproj` is the only build system and `CLAUDE.md`
  documents the file-registration rule.
- Unpinned web devDependencies / two React copies: not worth doing beyond
  documentation; `npm audit` still clean as of 2026-07-31.
- Preview build Task cancellation race (`SwiftPreviewHostView.run()`): real but
  low frequency (explicit multi-second builds); fix opportunistically.
- `SnippetEditorViewModel.hasUnsavedData` media identity comparison: LOW
  confidence, needs verification; investigate only if users report lost edits.

## Audit coverage note

**Round 2** was a standard-depth audit performed directly by the advisor (no
audit subagents), scoped to code landed since round 1 and to the two documents
that record prior decisions (`plans/README.md`, `Docs/security-overview.md`) —
nothing settled in either was re-reported. Files read in full: the quick-copy
and quick-capture feature sets, `MenuBarController`, `ClipboardMonitor`,
`Clipboard`, `SnippetsApp`, `PreviewTrust`, `SettingsView`, `SnippetStore`,
`SnippetsData`, `TrashView`, `TrashLifecycle`, and the relevant regions of
`ContentView`.

**Not audited in round 2**: preview param configs beyond `PreviewTrust`
(2026-07-21 work — the three test files there suggest it was built test-first),
`SyntaxHighlighter`, `LanguageDetector` rules, `MetalDisintegrationRenderer`,
`.xcodeproj` internals, `web/design-system` source, and the `ds-bundle` /
`.ds-sync` trees.

Plans 011–013 were written by the advisor; 014–016 were drafted by subagents
from advisor-verified excerpts, then reviewed by the advisor before landing.
