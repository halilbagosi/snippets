# Plan 009: Stop full-document web-preview reloads — incremental source and theme updates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift Sources/Snippets/Views/Components/Preview/WebPreviewView.swift Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`
> Plan 003 (CSP) touches the same files and is expected to land first —
> reconcile with its changes; its CSP and navigation delegate MUST survive
> this plan. On unexplained mismatches, STOP.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (changes the preview lifecycle; wrong staleness handling shows stale output)
- **Depends on**: 003 (same files; CSP must be preserved)
- **Category**: perf
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

Every accepted change to a web snippet — and every light/dark theme flip — rebuilds the entire HTML document and calls `loadHTMLString`, re-parsing the inlined React + ReactDOM + Babel runtimes (megabytes of minified JS) from scratch. Theme toggles reload everything to change two colors. Splitting "load the shell once" from "push the changed user source / theme" makes preview updates and theme flips near-instant and removes visible flicker.

## Current state

- `Sources/Snippets/Views/Components/Preview/WebPreviewView.swift:21-37`:
  ```swift
  func updateNSView(_ webView: WKWebView, context: Context) {
      guard context.coordinator.needsReload(sources: sources, flavor: flavor, isDark: theme.scheme == .dark) else { return }
      let appearance = WebPreviewHTMLBuilder.Appearance(isDark: ..., backgroundHex: ..., textHex: ...)
      let document = WebPreviewHTMLBuilder.document(linked: sources, entryFlavor: flavor, appearance: appearance, runtime: WebPreviewRuntime.shared)
      webView.loadHTMLString(document, baseURL: nil)
  }
  ```
  `Coordinator.needsReload` (`:39-46`) caches `lastSources`/`lastFlavor`/`lastIsDark` and returns false when nothing changed.
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — flavors: full-HTML passthrough, HTML fragment, JS (script + console shim), React (Babel `transform` + `eval`). Shared `skeleton(...)` builds head/body; appearance colors are inline CSS values in the skeleton (`background: \(appearance.backgroundHex)`).
- Tests: `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift` — string assertions on built documents, including `test_fullHTMLDocument_passesThroughUnchanged` (byte-identical passthrough must not regress).
- After plan 003: skeleton contains a CSP meta (`connect-src 'none'`, `'unsafe-inline'`, `'unsafe-eval'`); the Coordinator is a `WKNavigationDelegate` denying non-initial navigations. `evaluateJavaScript` calls from native are unaffected by CSP script-src, but any code they inject still runs under the document's CSP — fine, since it's inline-equivalent execution.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope**:
- `Sources/Snippets/Views/Components/Preview/WebPreviewView.swift`
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift`
- `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`

**Out of scope**:
- CSP policy content and the navigation delegate's rules (plan 003's decisions — preserve verbatim).
- `stripModuleSyntax` / transform semantics.
- Metal and Swift preview engines.

## Git workflow

- Branch: `advisor/009-web-preview-incremental-updates`
- Short sentence-case imperative subjects; commit per step.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Theme via CSS variables

In `skeleton()`, emit appearance colors as CSS custom properties on `:root` (`--preview-bg`, `--preview-text`) and reference them in the body styles. Add a builder function `WebPreviewHTMLBuilder.themeUpdateScript(appearance:) -> String` returning JS that sets those properties via `document.documentElement.style.setProperty(...)` (values passed through the existing `jsonLiteral` escaping helper).

**Verify**: build → exit 0; existing tests updated for the CSS-variable form still assert the hex values appear in the document.

### Step 2: Split reload decision into three tiers in `WebPreviewView`

Rework `Coordinator.needsReload` into a change classifier returning: `.none`, `.themeOnly`, `.sourceOnly`, or `.full`:

- `.themeOnly` (only `isDark`/appearance changed): `webView.evaluateJavaScript(themeUpdateScript)`.
- `.sourceOnly` (sources changed, same flavor, NOT the full-document passthrough flavor): step 3.
- `.full` (flavor changed, passthrough documents, first load, or a JS error fallback): current `loadHTMLString` path.

**Verify**: build → exit 0.

### Step 3: Push source changes without reloading the shell

Add `WebPreviewHTMLBuilder.sourceUpdateScript(linked:entryFlavor:) -> String?` producing JS that (a) clears the preview root/console output, and (b) re-executes the user program the same way the initial document does (for HTML fragments: replace root innerHTML; for JS: re-eval the wrapped program; for React: `Babel.transform` + eval + re-render into the root). Return `nil` for the passthrough flavor (forces `.full`). This requires factoring the per-flavor "user program" generation out of the document builders so the document path and the update path share one source of truth — do that factoring rather than duplicating strings. Guard staleness: each update script sets a monotonically increasing `window.__previewGeneration` and bails if a newer generation already ran.

If a `sourceOnly` `evaluateJavaScript` completes with an error, fall back to a `.full` reload (in the completion handler).

**Verify**: build → exit 0; new unit tests (below) pass.

### Step 4: Tests

**Verify**: full test command → exit 0.

## Test plan

Extend `WebPreviewHTMLBuilderTests.swift` (same string-assertion style, stub runtime):

1. `themeUpdateScript` contains both custom-property names and the escaped hex values.
2. `sourceUpdateScript` for JS flavor contains the user code and the generation guard; returns `nil` for full-document passthrough.
3. React `sourceUpdateScript` routes through `Babel.transform` (substring check) — same expectation the document tests use.
4. The initial document and the update script embed the same user-program payload for a given source (assert the shared factored function is used — e.g. both outputs contain an identical marker substring).
5. Passthrough byte-identity test still green.

WKWebView behavior (evaluateJavaScript plumbing) is manual-verification territory; note it in the PR description.

## Done criteria

- [ ] Full test command exits 0 with the new builder tests
- [ ] `updateNSView` no longer unconditionally calls `loadHTMLString` on theme change (visible in diff; `evaluateJavaScript` path exists)
- [ ] CSP meta and `navigationDelegate` assignment from plan 003 still present (`grep -n "Content-Security-Policy" ...HTMLBuilder.swift`; `grep -n "navigationDelegate" ...WebPreviewView.swift`)
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Plan 003 has not landed (no CSP in skeleton) — coordinate ordering rather than implementing around it.
- The per-flavor factoring in step 3 balloons (e.g. the React document path turns out to depend on load-time-only state) — if the shared-payload refactor exceeds ~150 changed lines in the builder, stop and propose a narrower scope (theme-only fast path, step 1+2 without step 3).
- Any existing builder test can only pass by weakening its assertion (behavior change leaked into the document path).

## Maintenance notes

- The generation guard is the concurrency story; a future "run console output streaming" feature must respect it.
- If snippets ever legitimately need network (CSP opt-in per plan 003's notes), the update path must carry the same policy decisions as the load path.
- Deferred deliberately: measuring actual reload cost — if the maintainer wants numbers first, run with Instruments before/after.
