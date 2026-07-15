# Design: containing Swift-preview code execution

Output of plan 005 (design/spike plan — no production code changes). Placed in
`plans/` because `Docs/` is intentionally untracked and this decision document
must be versioned. Facts verified against the tree at the time of writing
(post plans 003/004).

## Threat model

**What runs.** The Swift live preview compiles the snippet source with
`xcrun swiftc` and `dlopen`s the resulting dylib into the Snippets process:

- `SwiftPreviewHarness.make(entry:helpers:)` splices the snippet body verbatim
  into a compile unit with an exported `@_cdecl` factory
  (`Sources/Snippets/Features/Preview/SwiftPreviewHarness.swift:44-52`). There
  are no restrictions on imports or top-level declarations.
- `SwiftPreviewBuilder.build(entry:helpers:)` compiles it
  (`Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift:71`,
  `compile` at `:140`) and `dlopen`s the dylib (`:85-97`). Global initializers
  in the snippet run at `dlopen` time — before the factory is ever called.
- The factory returns a live `NSView` hosted directly in the hierarchy
  (`CompiledSwiftView` in
  `Sources/Snippets/Views/Components/Preview/SwiftPreviewHostView.swift:111-119`).
  This in-process NSView contract is the crux of every containment option.

**When.** Only on an explicit user action: previews never start on their own
(`SwiftPreviewHostView.run()` at `SwiftPreviewHostView.swift:94`; the Run
prompt says "Compiles and runs this snippet inside Snippets"). The consent
surface therefore partially exists, but it asks "run?" not "trust?".

**With what authority.** The app is unsandboxed —
`ENABLE_APP_SANDBOX = NO` in both build configurations
(`Snippets.xcodeproj/project.pbxproj:819,843`) and there is no entitlements
file; `Snippets-Info.plist` declares only an icon. Previewed code runs with
the user's full ambient authority: filesystem, network, `Process` spawning,
persistence. Dylibs are never unloaded (`SwiftPreviewBuilder.swift:31-36` —
dlclose is unsafe once Swift metadata escapes), so a malicious snippet stays
resident for the app's lifetime.

**Current trust assumption.** All snippets are authored locally by the user,
so today this is the feature working as designed. The assumption breaks the
moment snippets arrive from anywhere untrusted: import, sync, a shared
library, or a casual paste of someone else's code. Previewing such a snippet
is arbitrary native code execution.

## Options

| | What changes | NSView contract | UX cost | Effort | Residual risk |
|---|---|---|---|---|---|
| **A. Consent gate** | Per-snippet "Run Swift previews for this snippet?" confirmation; decision remembered per content hash (reset on edit) | Unchanged (in-process) | One extra click per snippet version | **S** | Unchanged once consented — user is the boundary |
| **B. Sandboxed XPC helper** | Compile in main app; *execute* in a sandboxed XPC service (no network entitlement, temp-only file access); ship rendered output back | **Broken** — remote code cannot hand back an NSView. Realistic v1: static bitmap snapshots; interactivity needs `NSRemoteView`-style bridging (private API) or a frame/event protocol (large) | Previews become static images (v1); latency per frame | **L** | Sandbox escape of the helper only; main app protected |
| **C. Sandbox the whole app** | `ENABLE_APP_SANDBOX = YES` + entitlements | Unchanged | Invisible when it works | **M–L** | **Does not contain previews**: dylib still loads in-process with the app's (now sandboxed) authority. `xcrun swiftc` subprocess likely breaks under sandbox (exec of external tools denied), `dlopen` of freshly written unsigned dylibs raises library-validation questions, `MediaManager` paths need entitlements. Complement to B, not an alternative |
| **D. Import allowlist** | Reject harness output importing beyond SwiftUI/AppKit/Foundation | Unchanged | Rejects legitimate snippets using other frameworks | **S** | **Not a security boundary**: Foundation alone reaches files, network (`URLSession`), and `Process`. Defense-in-depth UX only |

Notes on B (the only real containment):
- Compilation must stay in the main app (or a *differently*-profiled helper):
  sandbox profiles typically deny exec of `xcrun`/`swiftc`. The helper only
  needs to `dlopen` a dylib the app hands it and render.
- An XPC service embedded in the app bundle requires a real Xcode target —
  SPM cannot build app-embedded XPC services. The dual build system means the
  xcodeproj becomes load-bearing for a feature, not just packaging.
- The dylib cache atomicity work from plan 004 moves with execution — it is
  about artifact integrity, not where the compile runs.

## Spike findings

Spike skipped: the recommendation below does not depend on the risky
assumption. The one experiment worth running before implementing B — whether
a sandboxed process can `dlopen` an unsigned, freshly-compiled dylib and
render an offscreen `NSHostingView` to a bitmap — is cheap to do as step 1 of
B's implementation plan, and B is not the immediate recommendation.

## Recommendation

**Staged: A now, B before any import/sharing feature ships.**

- **A immediately** (S effort): the preview is already user-triggered; upgrade
  the Run prompt to an informed-consent gate. First run of a given content
  hash shows "This compiles and runs the snippet's code inside Snippets with
  full access to your files and network. Run it?" with a per-hash remembered
  choice (`SwiftPreviewHostView` already tracks `builtCode`; persist consent
  keyed by `Harness.hash`). Honest about the boundary: it protects the
  local-authorship trust model, not against a determined attacker the user
  says yes to.
- **B when snippets can arrive from outside** (L effort, static-image v1):
  consent is not an acceptable gate for content the user didn't write —
  "preview" must not mean "execute with my authority". Import/sharing work is
  **blocked** on B (or on shipping import without Swift preview for imported
  snippets, which is also acceptable as an interim).
- **C** only as part of B (the helper is sandboxed; sandboxing the main app is
  a separate hardening decision with its own breakage list).
- **D** optionally as UX polish inside A's dialog ("this snippet imports
  Network"), never advertised as protection.

## Implementation plan outline (for the future executor)

**Phase A (next):**
- `SwiftPreviewHostView.swift`: replace the bare Run button flow with a
  consent state — new `Phase.awaitingConsent`; copy above; "Always for this
  snippet version" persists `Harness.hash` into a `Set<String>` stored via
  `AppearanceSettings`-style persistence (or a small `PreviewConsentStore`).
- `SwiftPreviewHarness.hash` is already content-addressed; edits naturally
  reset consent.
- Tests: consent-store logic (grant, recall, reset-on-hash-change) — pure
  logic, in-memory.
- No entitlements/build-setting changes.

**Phase B (gates import/sharing):**
1. Spike (timeboxed): sandboxed helper `dlopen`s an app-supplied dylib,
   renders `NSHostingView` offscreen to a bitmap, ships it over XPC.
2. New Xcode XPC-service target (xcodeproj-only — document the SPM asymmetry
   in CLAUDE.md); entitlements: sandbox on, no network, no user files.
3. Main app keeps compile + cache (`SwiftPreviewBuilder` splits into
   `compile` (app) and `execute` (helper proxy)); the `Phase.ready` contract
   changes from `() -> NSView?` to an image/stream provider;
   `CompiledSwiftView` renders the bitmap.
4. Interactivity (if ever): frame/event protocol or `NSRemoteView`
   investigation — explicitly out of v1.
5. Test strategy: harness/consent logic unit-tested as today; the XPC
   round-trip gets an integration test behind a toolchain-availability skip
   (pattern: `SwiftPreviewBuilderTests.test_build_recoversFromCorruptCachedDylib`).

**Open question for the maintainer** (not blocking A): whether an interim
"imported snippets have no Swift preview" rule is acceptable product-wise; if
yes, B can wait until sharing is actually scheduled.
