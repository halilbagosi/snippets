# Plan 003: Lock down the web preview — CSP, navigation blocking, and no silent network egress

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift Sources/Snippets/Views/Components/Preview/WebPreviewView.swift Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`
> On any change, compare the "Current state" excerpts against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (a too-strict CSP breaks legitimate snippets; the React/Babel inline runtime must keep working)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

The live web preview executes snippet JavaScript inside a WKWebView with JavaScript enabled, no Content-Security-Policy, and no navigation restrictions. Snippet code can therefore make arbitrary outbound network requests (`fetch`, XHR, WebSockets, image beacons), load remote second-stage scripts, or navigate the view to a remote page. The app is unsandboxed (`ENABLE_APP_SANDBOX = NO`), so this is the easiest exfiltration/phone-home channel for any untrusted snippet the user previews. A restrictive CSP plus a navigation-denying delegate closes the network channel while keeping inline JS (the whole point of the preview) working.

## Current state

- `Sources/Snippets/Views/Components/Preview/WebPreviewView.swift:13-19`:
  ```swift
  func makeNSView(context: Context) -> WKWebView {
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.setValue(false, forKey: "drawsBackground")   // private KVC — replace (step 3)
      return webView
  }
  ```
  `updateNSView` (`:21-37`) rebuilds the document and calls `webView.loadHTMLString(document, baseURL: nil)`. There is a `Coordinator` class (`:39+`) holding change-detection state (`needsReload`), but no `WKNavigationDelegate`.
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — builds the full HTML document. The shared `skeleton(appearance:body:extraCSS:headExtras:)` (`:384-419`) emits:
  ```html
  <!doctype html>
  <html>
  <head>
  <meta charset="utf-8">
  <meta name="color-scheme" content="...">
  <style> ... </style>\(headExtras)
  </head>
  <body> ... </body>
  ```
  No CSP meta anywhere. Snippet JS runs via inline `<script>` (including Babel-transformed React via `(0, eval)(...)` around `:162-185, 230-244`); the React/ReactDOM/Babel runtimes are inlined as script text from bundled resources — everything is inline, nothing is fetched.
- Important passthrough: `test_fullHTMLDocument_passesThroughUnchanged` in `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift:27-30` — when the snippet is already a full `<!DOCTYPE html>` document, `document(...)` returns it byte-identical. A CSP injected into `skeleton()` will not cover this passthrough path; the navigation delegate + a CSP applied at the WKWebView level must (see step 2 note).
- Test conventions: `WebPreviewHTMLBuilderTests.swift` — plain `XCTestCase`, builds documents with a stub `ReactRuntime(react: "/*react-rt*/", ...)` and asserts substring presence. Match it.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope**:
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift`
- `Sources/Snippets/Views/Components/Preview/WebPreviewView.swift`
- `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`

**Out of scope**:
- `stripModuleSyntax` and any transform logic — separate recorded finding.
- The Metal and Swift preview engines (plans 004/005 territory).
- Incremental-reload performance work (plan 009) — do not restructure the load lifecycle here.
- Adding a per-snippet "allow network" UI toggle — note it as follow-up only.

## Git workflow

- Branch: `advisor/003-web-preview-csp`
- Short sentence-case imperative commit subjects; commit per step.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Inject a restrictive CSP into `skeleton()`

Add to the `<head>` in `skeleton()` (before the `<style>` tag):

```html
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'">
```

Rationale (inline as a code comment): everything the preview legitimately needs is inline — `'unsafe-inline'` for the embedded runtimes and snippet code, `'unsafe-eval'` because the React path executes Babel output via `eval`; `connect-src 'none'` is the actual security payoff (no fetch/XHR/WebSocket egress); `img-src data:` keeps data-URI images working while blocking remote beacons.

**Verify**: build → exit 0; existing `WebPreviewHTMLBuilderTests` — expect `test_fullHTMLDocument_passesThroughUnchanged` still green (passthrough must stay byte-identical) and other document tests still green.

### Step 2: Add a navigation-denying `WKNavigationDelegate`

In `WebPreviewView.swift`, make the existing `Coordinator` conform to `WKNavigationDelegate`, set `webView.navigationDelegate = context.coordinator` in `makeNSView`, and implement `webView(_:decidePolicyFor navigationAction:decisionHandler:)`:

- Allow when `navigationAction.request.url` is nil, `about:blank`, or the load kind is the initial `loadHTMLString` (these arrive as `.other` with `about:`/nil URLs).
- Deny (`.cancel`) everything else — especially `http(s)` URLs, whether top-level navigations or triggered by snippet JS.

This also covers the full-document passthrough path that the skeleton CSP cannot reach (subresource loads inside a passthrough document are governed by CSP only if the document has one; navigation attempts are caught here — note this residual gap in the code comment and in Maintenance notes).

**Verify**: build → exit 0.

### Step 3: Replace the private `drawsBackground` KVC

Replace `webView.setValue(false, forKey: "drawsBackground")` with the public API:

```swift
webView.underPageBackgroundColor = .clear
```

If transparency visibly regresses (cannot be verified headlessly — note it), keep the new line and flag for manual UI review.

**Verify**: `grep -n "setValue" Sources/Snippets/Views/Components/Preview/WebPreviewView.swift` → no matches; build → exit 0.

### Step 4: Tests

See Test plan.

**Verify**: test command → all pass including new tests.

## Test plan

Extend `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift` (same style — substring assertions on the built document):

1. Each flavor's generated document contains `Content-Security-Policy` and `connect-src 'none'` (loop over HTML/JS/React flavors as existing tests do).
2. The full-document passthrough still returns input byte-identical (existing test must keep passing — do not "fix" it by injecting CSP into passthrough).
3. The CSP meta appears before the first `<style>` tag in the skeleton output.

The navigation delegate is UI code (WKWebView); no unit test required — note manual verification in the PR description instead.

## Done criteria

- [ ] Test command exits 0, including ≥ 2 new CSP tests
- [ ] `grep -n "Content-Security-Policy" Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` → 1 match (in `skeleton`)
- [ ] `grep -n "navigationDelegate" Sources/Snippets/Views/Components/Preview/WebPreviewView.swift` → ≥ 1 match
- [ ] `grep -n "setValue" .../WebPreviewView.swift` → 0 matches
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- The skeleton excerpt doesn't match (drift).
- After adding the CSP, the React flavor tests fail in a way suggesting the Babel/eval path is blocked even with `'unsafe-eval'` — do not weaken the CSP further than the policy in step 1 without reporting.
- You find an existing feature that legitimately requires snippet network access (e.g. a documented remote-import feature) — the `connect-src 'none'` decision needs the maintainer.

## Maintenance notes

- Residual gap: a snippet that is a *complete* HTML document bypasses the skeleton CSP; only the navigation delegate constrains it, and subresource fetches inside it are not blocked. Follow-up options: inject CSP into passthrough documents too (breaks byte-identity contract), or gate passthrough behind user consent.
- If a "snippet needs network" feature is ever wanted, implement it as an explicit per-snippet opt-in that swaps `connect-src 'none'` for an allowlist — never a global relaxation.
- Plan 009 (incremental preview updates) touches the same files; it must preserve the CSP and delegate.
