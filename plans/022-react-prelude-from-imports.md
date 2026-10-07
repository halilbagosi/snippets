# Plan 022: Bind React globals from the snippet's own imports instead of a fixed hook list

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`
> (includes uncommitted edits). If either file changed since this plan was
> written (plan 021 also edits the builder, in `glslDocument`, which is
> expected), compare the "Current state" excerpts against the live code before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

React previews run snippets as plain scripts against the bundled UMD
`React`/`ReactDOM` globals. Every `import ... from "react"` line is stripped,
and a **fixed** line is prepended in its place:

```js
const { useState, useEffect, useRef, useMemo, useCallback, useContext,
        useReducer, useLayoutEffect, useId, Fragment, createElement } = React;
```

That breaks common snippets in two ways:

1. **Names outside the list are undefined.** `import { forwardRef, memo, createContext } from "react"`
   → `forwardRef is not defined`. The same happens with `createPortal` from
   `react-dom`, `useTransition`, `useImperativeHandle` and `startTransition`.
2. **Names the snippet declares itself collide.** CodePen-style React often
   contains `const { useState, useEffect } = React;`, which with the prelude
   becomes a second `const useState` in the same scope:
   "Identifier 'useState' has already been declared", and the preview fails.
   A snippet that defines its own `function useId()` fails the same way.

After this plan, the prelude:

- binds what the snippet actually imports from react/react-dom, including
  aliases;
- keeps a broader fallback list for snippets with no imports;
- leaves out any name the snippet (or its connected helpers) declares, or that
  another import binds.

## Current state

- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — builds
  preview documents. `reactSource(code:helperScript:policy:)` (`private static`,
  starts at line 717) assembles the evaluated React source and is used by both
  the full-document path (`:592`) and the incremental-update path (`:1135`).

`WebPreviewHTMLBuilder.swift:726-731` (inside `reactSource`):
```swift
        let fullCode = helperScript + "\n" + code
        let cdnSpecifiers = CDNModules(
            detected: unsupportedImports(in: fullCode), policy: policy
        )
        let bindings = cdnSpecifiers.allowed.isEmpty ? "" : cdnImportBindings(in: fullCode)
        var source = stripModuleSyntax(code, rewriteDefaultExport: true)
```

`WebPreviewHTMLBuilder.swift:763-767`:
```swift
        source = bindings + """
        const { useState, useEffect, useRef, useMemo, useCallback, useContext,
                useReducer, useLayoutEffect, useId, Fragment, createElement } = React;

        """ + source
```

- `cdnImportBindings(in:)` (`:782`) emits `const` bindings for npm imports
  (for example `import { memo } from "some-lib"`). The prelude must not
  re-declare those names.
- The runtime exposes `ReactDOM` as a global (`:699` calls `ReactDOM.createRoot`).
- Conventions: testable helpers are `static` and internal, with a doc comment
  ending "Internal (not private) so tests can pin …" (see `stripModuleSyntax`,
  `:845-850`). Regexes are built with `guard let regex = try? NSRegularExpression(...) else { ... }`
  (see `:783-784`); never use `try!`.
- Tests: `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`. The existing
  `test_react_*` test at `:741-744` asserts a document using `useState` still
  contains it, and must keep passing.

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/WebPreviewHTMLBuilderTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Suggested executor toolkit

- The `verify` skill (if present) for step 5's runtime check.

## Scope

**In scope**:
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — the prelude in `reactSource`, plus three new static helpers
- `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`

**Out of scope** (do NOT touch):
- `stripModuleSyntax`, `unsupportedImports`, `cdnImportBindings`,
  `reactMountTarget`. They have known edge cases of their own, which belong
  to a separate, larger lexer rewrite. Changing them here widens the risk
  surface.
- The bundled runtime and the CSP/consent logic.

## Git workflow

- Branch: `advisor/022-react-prelude-from-imports`
- Commit message: `Bind React globals from the snippet's imports, not a fixed hook list`
- `git add` the two in-scope paths only. Do NOT push unless instructed.

## Steps

### Step 1: Failing tests

Add a `// MARK: React prelude` section to `WebPreviewHTMLBuilderTests.swift`:

```swift
    func test_prelude_bindsNamesImportedFromReact() {
        let prelude = WebPreviewHTMLBuilder.reactPrelude(for:
            "import { forwardRef, memo, createContext } from \"react\";\nexport default memo(forwardRef(() => null));")
        for name in ["forwardRef", "memo", "createContext", "useState"] {
            XCTAssertTrue(prelude.contains(name), "missing \(name)")
        }
        XCTAssertTrue(prelude.contains("} = React;"))
    }

    func test_prelude_bindsReactDOMImportsFromReactDOM() {
        let prelude = WebPreviewHTMLBuilder.reactPrelude(for:
            "import { createPortal } from \"react-dom\";\nimport { createRoot } from 'react-dom/client';")
        XCTAssertTrue(prelude.contains("const { createPortal, createRoot } = ReactDOM;"))
    }

    func test_prelude_omitsNamesTheSnippetDeclares() {
        let prelude = WebPreviewHTMLBuilder.reactPrelude(for:
            "const { useState, useEffect } = React;\nfunction useId() { return 1 }\nfunction App() { return null }")
        XCTAssertFalse(prelude.contains("useState"))
        XCTAssertFalse(prelude.contains("useEffect"))
        XCTAssertFalse(prelude.contains("useId"))
        XCTAssertTrue(prelude.contains("useRef"))
    }

    func test_prelude_honorsAliasesAndSkipsTypeImports() {
        let prelude = WebPreviewHTMLBuilder.reactPrelude(for:
            "import React, { useState as useS, type FC } from 'react';\nimport type { ReactNode } from 'react';\nimport * as R from 'react';")
        XCTAssertTrue(prelude.contains("useState: useS"))
        XCTAssertTrue(prelude.contains("const R = React;"))
        XCTAssertFalse(prelude.contains("FC"))
        XCTAssertFalse(prelude.contains("ReactNode"))
        XCTAssertFalse(prelude.contains("const React ="))
    }

    func test_prelude_omitsNamesBoundByOtherImports() {
        let prelude = WebPreviewHTMLBuilder.reactPrelude(for:
            "import { memo, Children as Kids } from 'some-lib';\nimport { useState } from 'react';")
        XCTAssertFalse(prelude.contains("memo"))
        XCTAssertTrue(prelude.contains("Children"))   // only `Kids` is bound by some-lib
    }

    func test_reactDocument_snippetDestructuringReact_isNotDeclaredTwice() {
        let doc = document("const { useState } = React;\nexport default function App() { const [n] = useState(0); return <p>{n}</p> }", .react)
        XCTAssertFalse(doc.contains("const { useState, useEffect"))
    }
```

**Verify**: build fails to compile because `reactPrelude(for:)` does not
exist. That is the expected red state.

### Step 2: Add the helpers

Add these to `WebPreviewHTMLBuilder`, directly above `reactSource`. This code
was prototyped and checked against every test in step 1. Keep it as written
unless the build requires small adjustments.

```swift
    /// Names bound from the `React` global for snippets that use them without
    /// importing (CodePen style). Imported names are added on top.
    static let reactFallbackNames = [
        "useState", "useEffect", "useRef", "useMemo", "useCallback", "useContext",
        "useReducer", "useLayoutEffect", "useId", "useTransition", "useDeferredValue",
        "useImperativeHandle", "useSyncExternalStore", "Fragment", "createElement",
        "createContext", "forwardRef", "memo", "startTransition", "Children",
        "cloneElement", "isValidElement"
    ]

    /// The `const` lines that stand in for the stripped react/react-dom
    /// imports: what the snippet imports (aliases included) plus the fallback
    /// names, minus anything the snippet declares itself or another import
    /// binds. A name declared twice is a SyntaxError that kills the preview.
    /// `code` is the entry plus its connected helpers.
    /// Internal (not private) so tests can pin the bindings.
    static func reactPrelude(for code: String) -> String {
        var react: [(imported: String, local: String)] = reactFallbackNames.map { ($0, $0) }
        var reactDOM: [(imported: String, local: String)] = []
        var aliases: [(local: String, global: String)] = []
        // Names other imports bind (npm modules via `cdnImportBindings`,
        // relative imports via connected snippets) must not be re-declared.
        var boundElsewhere = Set<String>()

        let pattern = #"(?m)^[ \t]*import\s+(?!type\b)([^;'"]*?)\s*from\s*["']([^"'\n]+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let clauseRange = Range(match.range(at: 1), in: code),
                      let specRange = Range(match.range(at: 2), in: code) else { continue }
                let clause = String(code[clauseRange])
                let spec = String(code[specRange])
                let isReact = spec == "react" || spec.hasPrefix("react/")
                let isReactDOM = spec == "react-dom" || spec.hasPrefix("react-dom/")
                guard isReact || isReactDOM else {
                    boundElsewhere.formUnion(importedLocalNames(in: clause))
                    continue
                }
                let global = isReact ? "React" : "ReactDOM"
                var head = clause
                if let open = clause.firstIndex(of: "{"), let close = clause.firstIndex(of: "}"), open < close {
                    head = String(clause[..<open])
                    for part in clause[clause.index(after: open)..<close].split(separator: ",") {
                        let entry = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !entry.isEmpty, !entry.hasPrefix("type ") else { continue }
                        let pieces = entry.components(separatedBy: " as ")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        let binding = (imported: pieces[0], local: pieces.count == 2 ? pieces[1] : pieces[0])
                        if isReact { react.append(binding) } else { reactDOM.append(binding) }
                    }
                }
                // Default or namespace import (`R`, `* as R`); the global's own
                // name needs no binding.
                let name = head.replacingOccurrences(of: "* as", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", \t\n"))
                if !name.isEmpty, name != global { aliases.append((name, global)) }
            }
        }

        var declared = Set<String>()
        func keep(_ local: String) -> Bool {
            !boundElsewhere.contains(local) && !declaresBinding(local, in: code)
                && declared.insert(local).inserted
        }
        func destructure(_ bindings: [(imported: String, local: String)], from global: String) -> String? {
            let entries = bindings.filter { keep($0.local) }
                .map { $0.imported == $0.local ? $0.local : "\($0.imported): \($0.local)" }
            return entries.isEmpty ? nil : "const { \(entries.joined(separator: ", ")) } = \(global);"
        }
        var lines = aliases.filter { keep($0.local) }.map { "const \($0.local) = \($0.global);" }
        if let line = destructure(react, from: "React") { lines.append(line) }
        if let line = destructure(reactDOM, from: "ReactDOM") { lines.append(line) }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n\n"
    }

    /// Local names an import clause binds: `D`, `* as N`, `{ a, b as c }`.
    static func importedLocalNames(in clause: String) -> [String] {
        clause.replacingOccurrences(of: "* as", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: "{},"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("type ") }
            .compactMap { $0.components(separatedBy: " as ").last?.trimmingCharacters(in: .whitespaces) }
    }

    /// Whether `code` declares `name` itself: `const/let/var/function/class
    /// name`, or a destructuring like `const { name } = React`.
    static func declaresBinding(_ name: String, in code: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"\b(?:const|let|var|function|class)\s+"# + escaped + #"\b"#,
            #"\b(?:const|let|var)\s*\{[^}]*\b"# + escaped + #"\b[^}]*\}\s*="#
        ]
        return patterns.contains { code.range(of: $0, options: .regularExpression) != nil }
    }
```

**Verify**: build command → `** BUILD SUCCEEDED **`; focused tests → the five
`test_prelude_*` tests pass. The document-level test still fails until step 3.

### Step 3: Use the prelude in `reactSource`

Replace the fixed block at `:763-767` with:

```swift
        source = bindings + reactPrelude(for: fullCode) + source
```

`fullCode` is already defined at the top of `reactSource`. It includes the
connected helpers, so a name a helper declares or imports is also excluded.

**Verify**: focused tests command → `** TEST SUCCEEDED **`, including
`test_reactDocument_snippetDestructuringReact_isNotDeclaredTwice` and the
existing `:741-744` `useState` test.

### Step 4: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`.

### Step 5: Runtime check (only if you can launch the app)

Use the `verify` skill, or build and run the app. Create two React snippets
and open each one's preview:

1. ```jsx
   import { forwardRef, memo } from "react";
   const Box = memo(forwardRef((props, ref) => <div ref={ref}>box</div>));
   export default function App() { return <Box /> }
   ```
2. ```jsx
   const { useState } = React;
   export default function App() { const [n, setN] = useState(0); return <button onClick={() => setN(n + 1)}>{n}</button> }
   ```

**Expected**: both render, with no "is not defined" or "already been declared"
error in the preview console. If you cannot launch the app, say so in your
report.

## Test plan

- Five unit tests on `reactPrelude(for:)`: imported names, react-dom, self
  declarations, aliases and type imports, and names bound by other imports.
  One document-level test for the double declaration.
- Existing `WebPreviewHTMLBuilderTests` (React, linked sources, CDN bindings)
  must pass unchanged.

## Done criteria

- [ ] `grep -n "useReducer, useLayoutEffect, useId, Fragment, createElement } = React" Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` returns nothing
- [ ] `grep -n "reactPrelude(for: fullCode)" Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` → 1 match
- [ ] Full tests → `** TEST SUCCEEDED **`
- [ ] Step 5 done, or reported as not run
- [ ] `plans/README.md` status row updated

## STOP conditions

- `reactSource` no longer contains the fixed prelude shown in "Current state".
- An existing test fails because it asserts the exact old prelude text. Report
  which one; don't rewrite it without saying so.
- Step 5 shows "React is not defined" or "ReactDOM is not defined". That
  would mean the runtime globals differ from what this plan assumes.

## Maintenance notes

- `declaresBinding` is a regex check, not a parser. It treats a declaration
  *anywhere* in the code (even inside a nested function) as a top-level one,
  so that name is left out of the prelude. That only matters if the same name
  is also used at top level from React, which is rare. A real JS lexer, the
  deferred "one import scanner" rewrite, would make it exact.
- A new React API that snippets commonly use without importing belongs in
  `reactFallbackNames`.
