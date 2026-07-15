# Plan 005: Design plan — contain Swift-preview code execution (sandboxing / consent architecture)

> **Executor instructions**: This is a **design/spike plan**, not a build plan.
> The deliverable is a written design document plus at most a throwaway spike —
> NO production code changes. Follow the steps, honor STOP conditions, and when
> done update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Features/Preview/ Sources/Snippets/Views/Components/Preview/ Snippets.xcodeproj/project.pbxproj`
> Drift here is informational (the design must describe the current code), not
> an automatic STOP unless the Swift preview engine was removed or already
> sandboxed.

## Status

- **Priority**: P2
- **Effort**: L (design M, eventual implementation L — implementation is NOT this plan)
- **Risk**: LOW for this plan (docs only); the implemented change is HIGH-risk architecture work
- **Depends on**: none (informs future implementation; plan 004 is independent)
- **Category**: security / direction
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

The Swift live-preview feature compiles snippet source with `xcrun swiftc` and `dlopen`s the resulting dylib **into the app's own process**. Global initializers in the snippet run at load time. The app builds with `ENABLE_APP_SANDBOX = NO` (`Snippets.xcodeproj/project.pbxproj:819,843`) and no entitlements file, so previewed code runs with the user's full ambient authority: filesystem, network, process spawning, persistence. Today snippets are authored locally by the user, so this is the feature working as designed — but the moment snippets arrive from anywhere untrusted (import [see the export/import direction finding], sync, a shared library, or a casual paste), previewing one is arbitrary native code execution. The maintainer needs a decided architecture before building any snippet-sharing feature; this plan produces that decision document.

## Current state (facts the design must account for)

- `Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift` — actor/singleton (`SwiftPreviewBuilder.shared`); `build(entry:helpers:)` writes source to `~/Library/Caches/.../SnippetPreviews/<hash>.swift`, runs `/usr/bin/xcrun swiftc -target arm64-apple-macos26.0 -parse-as-library -emit-library -Onone -o <hash>.dylib`, then:
  ```swift
  guard let handle = dlopen(dylibURL.path, RTLD_NOW) else { ... }
  guard let symbol = dlsym(handle, harness.symbolName) else { ... }
  typealias Factory = @convention(c) () -> UnsafeMutableRawPointer
  let factory = unsafeBitCast(symbol, to: Factory.self)
  return { Unmanaged<NSView>.fromOpaque(factory()).takeRetainedValue() }
  ```
  The contract with the UI is a `@MainActor () -> NSView?` factory — the compiled snippet returns a live **NSView** hosted directly in the hierarchy (`SwiftPreviewHostView.swift` → `CompiledSwiftView: NSViewRepresentable`). This in-process NSView contract is the crux: an out-of-process design cannot hand back an NSView pointer.
- `Sources/Snippets/Features/Preview/SwiftPreviewHarness.swift` — splices the snippet body verbatim into a compile unit (`:44-53`); no restrictions on imports or top-level declarations.
- Previews are **explicitly user-triggered** (a Run button; `SwiftPreviewHostView.run()` at `:94`), not automatic on selection — the consent surface partially exists.
- `ENABLE_APP_SANDBOX = NO` in both build configurations; `MediaManager` writes to Application Support; the web preview (WKWebView) and Metal preview coexist and already run out-of-process (WebKit) / on the GPU respectively.
- Related plans: 003 locks down the web preview; 004 makes the dylib cache crash-safe.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (for spike only, in a scratch worktree) | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |

## Scope

**In scope** (deliverables):
- `Docs/design/swift-preview-sandboxing.md` (create; note `Docs/` is untracked by decision — if it must be tracked, put the doc at `plans/005-design-output.md` instead and say so)
- Optional throwaway spike code in a scratch directory outside the repo

**Out of scope**:
- ANY change to production sources, entitlements, or build settings.
- Implementing the chosen option (a future plan).

## Git workflow

- No production branches. If the design doc lands in-repo, branch `advisor/005-swift-preview-sandboxing-design`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Characterize the exposure precisely

Read the four preview files listed above plus `Snippets-Info.plist`. Document in the design doc: what runs, when (user-triggered Run), with what authority (unsandboxed app), and what the trust model currently assumes (all snippets authored locally by the user).

**Verify**: the doc's "Threat model" section exists and cites file:line for each claim.

### Step 2: Evaluate the candidate architectures

For each option, document: what changes, what the NSView contract becomes, UX cost, implementation effort (coarse S/M/L), and residual risk.

- **A. Consent gate (minimum)**: keep in-process execution; add a per-snippet "Run Swift previews for this snippet" confirmation with a remembered decision, reset when snippet content changes hash. Near-zero architectural cost; residual risk unchanged once consented.
- **B. XPC helper with its own sandbox**: compile AND execute in a sandboxed XPC service (no network entitlement, temp-dir-only file access); render the NSView remotely and ship frames/interaction via `NSRemoteView`-style bridging or a bitmap/stream protocol (this is the hard part — assess honestly whether interactive previews survive; a static-image preview may be the realistic v1).
- **C. Sandbox the whole app** (`ENABLE_APP_SANDBOX = YES` + entitlements): assess what breaks — `xcrun swiftc` subprocess (likely fails under sandbox), `dlopen` of freshly written dylibs (library-validation questions), `MediaManager` paths. Likely requires B anyway; document as complement, not alternative.
- **D. Restrict at the source level**: reject snippets whose harness output imports beyond an allowlist (SwiftUI/AppKit/Foundation). Document why this is NOT a security boundary (Foundation alone reaches files/network/Process) — include it only as defense-in-depth UX.

**Verify**: doc contains a comparison table of A–D with the columns above.

### Step 3: (Optional spike, timeboxed ~2h) Validate the riskiest assumption of the preferred option

If B is preferred: spike whether a minimal sandboxed helper process can run `xcrun swiftc` at all (sandbox profiles typically deny exec of external tools — the likely answer shapes the design: compile in the main app, execute in the helper). Spike lives outside the repo; record findings + the spike's location in the doc.

**Verify**: doc has a "Spike findings" section or an explicit "spike skipped because…" line.

### Step 4: Recommend and specify the follow-up plan

Pick one option (a staged recommendation is fine — e.g. "A now, B when import/sharing ships"), and write the outline of the implementation plan: files touched, new targets (XPC service needs an Xcode target — note the dual-build-system implication: SPM cannot build an app-embedded XPC service, so the xcodeproj becomes load-bearing), migration steps, and the test strategy.

**Verify**: doc ends with "Recommendation" and "Implementation plan outline" sections.

## Test plan

Not applicable (design doc). The doc itself must specify the future implementation's test strategy.

## Done criteria

- [ ] Design doc exists at the agreed path with sections: Threat model, Options A–D comparison, Spike findings (or skip rationale), Recommendation, Implementation plan outline
- [ ] Every factual claim about current code cites `file:line`
- [ ] No production source/build files modified (`git status` shows only the doc and plans/README.md)
- [ ] `plans/README.md` status row updated

## STOP conditions

- The Swift preview engine has been removed or already moved out of process (drift) — report, don't design for dead code.
- The spike suggests option B is infeasible on macOS 26 within reasonable effort AND option A is deemed insufficient — surface to the maintainer rather than inventing option E unilaterally (proposing E in the doc as an open question is fine).

## Maintenance notes

- This design gates any snippet **import/sharing** feature (see the export/import direction finding in plans/README.md): do not ship import while previews execute untrusted code in-process without at least option A.
- Plans 003 (web CSP) and 004 (dylib cache) are compatible with all options and should not wait for this.
