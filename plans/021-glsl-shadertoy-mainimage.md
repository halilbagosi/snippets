# Plan 021: Run Shadertoy-style GLSL (`mainImage`) in the web preview

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift`
> (includes uncommitted edits). If either file changed since this plan was
> written, compare the "Current state" excerpts against the live code before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (plan 022 edits the same file in a different function; either order works)
- **Category**: bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

The most common GLSL snippet people paste is a Shadertoy shader:

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(fragCoord / iResolution.xy, 0.5, 1.0);
}
```

The language detector treats `mainImage(out vec4` as decisive GLSL evidence
(`Services/LanguageDetectorRules.swift:39`), so these snippets go to the WebGL
preview. That preview adds a header (version, precision, `iTime`,
`iResolution`, `iMouse`, `out vec4 fragColor`) but never a `main()`. The
shader fails to link ("missing main") and the preview shows an error for every
Shadertoy paste. After this plan, a shader that defines `mainImage` and no
`main` gets the standard one-line entry point.

## Current state

- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — builds the
  HTML document for web previews. `glslDocument(code:appearance:)` starts at
  line 928. Linked GLSL helpers are concatenated before the entry
  (`:161-163`), so `code` here may contain several snippets.

`WebPreviewHTMLBuilder.swift:928-946`:
```swift
    private static func glslDocument(code: String, appearance: Appearance) -> String {
        // Fragment-only snippets (shadertoy-style) get a prelude declaring the
        // version, precision, standard uniforms and output; full shaders with
        // their own #version pass through untouched.
        let fragment: String
        if code.contains("#version") {
            fragment = code
        } else {
            fragment = """
            #version 300 es
            /*snippet-glsl-header*/
            precision highp float;
            uniform float iTime;
            uniform vec2 iResolution;
            uniform vec4 iMouse;
            out vec4 fragColor;
            \(code)
            """
        }
```

The runtime sets `iResolution` with `gl.uniform2f(uResolution, w, h)`
(around line 1032). **Keep `iResolution` a `vec2`.** Shadertoy declares it
`vec3`, but existing snippets written for this app divide by it as a vec2
(`gl_FragCoord.xy / iResolution`), which would fail to compile against a vec3.
Shadertoy code that uses `iResolution.xy` or `.x`/`.y` already works with a vec2.

Existing tests: `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift:759-777`
(`test_glsl_embedsShaderWithWebGLBoilerplateAndUniforms`,
`test_glsl_fullShaderWithVersionDirective_isNotWrappedWithHeader`). They use
the private helper `document(_ code:, _ flavor:)` defined at the top of the
test class. Testable helpers in the builder are `static` and internal (not
`private`) with a doc comment saying so; see `stripModuleSyntax` (`:850`).

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/WebPreviewHTMLBuilderTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Suggested executor toolkit

- If the `verify` skill is available (`.claude/skills/verify`), use it in
  step 4 to launch the app and check a real WebGL compile. Unit tests can only
  check the generated text.

## Scope

**In scope**:
- `Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` — `glslDocument` plus one new helper next to it
- `Tests/SnippetsTests/WebPreviewHTMLBuilderTests.swift` — the `// MARK: GLSL` section

**Out of scope** (do NOT touch):
- The `iResolution` type and the JS runtime that sets the uniforms (see above).
- Other Shadertoy uniforms (`iFrame`, `iTimeDelta`, `iChannel0-3`, `iDate`).
  Adding them can clash with shaders that declare them; that is a separate
  decision.
- Shaders that contain `#version` — they pass through untouched, as today.
- `MetalShaderSource.swift` (Metal, not GLSL).

## Git workflow

- Branch: `advisor/021-glsl-shadertoy-mainimage`
- Commit message: `Give Shadertoy-style GLSL snippets a main() that calls mainImage`
- `git add` the two in-scope paths only. Do NOT push unless instructed.

## Steps

### Step 1: Failing tests

In the `// MARK: GLSL` section of `WebPreviewHTMLBuilderTests.swift`, add:

```swift
    func test_glsl_shadertoyMainImage_getsMainEntryPoint() {
        let shader = "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n  fragColor = vec4(fragCoord / iResolution.xy, 0.5, 1.0);\n}"
        let doc = document(shader, .glsl)
        XCTAssertTrue(doc.contains("void main() { mainImage(fragColor, gl_FragCoord.xy); }"))
    }

    func test_glsl_shaderWithOwnMain_getsNoExtraEntryPoint() {
        let shader = "void mainImage(out vec4 c, in vec2 p) { c = vec4(1.0); }\nvoid main() { mainImage(fragColor, gl_FragCoord.xy); }"
        XCTAssertFalse(WebPreviewHTMLBuilder.needsMainImageEntry(shader))
        XCTAssertFalse(WebPreviewHTMLBuilder.needsMainImageEntry("void main() { fragColor = vec4(1.0); }"))
    }

    func test_glsl_commentedOutMain_stillGetsEntryPoint() {
        let shader = "// void main() { }\nvoid mainImage(out vec4 c, in vec2 p) { c = vec4(1.0); }"
        XCTAssertTrue(WebPreviewHTMLBuilder.needsMainImageEntry(shader))
    }
```

**Verify**: build fails to compile because `needsMainImageEntry` does not
exist. That is the expected red state.

### Step 2: Add the detector helper

Directly above `glslDocument`, add:

```swift
    /// Whether a fragment-only shader is Shadertoy-style: it defines
    /// `mainImage` but no `main`, so the preview must supply the entry point.
    /// Comments are ignored so a commented-out `main` doesn't count.
    /// Internal (not private) so tests can pin it.
    static func needsMainImageEntry(_ code: String) -> Bool {
        let uncommented = code
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
        let definesMainImage = uncommented.range(of: #"\bvoid\s+mainImage\s*\("#, options: .regularExpression) != nil
        let definesMain = uncommented.range(of: #"\bvoid\s+main\s*\("#, options: .regularExpression) != nil
        return definesMainImage && !definesMain
    }
```

**Verify**: build command → `** BUILD SUCCEEDED **`.

### Step 3: Append the entry point in the header branch

In `glslDocument`, in the `else` branch only (no `#version`), append the
entry point after `\(code)` when `needsMainImageEntry(code)` is true. Target
shape:

```swift
        } else {
            // Shadertoy shaders define `mainImage(out vec4, in vec2)` and rely
            // on the host for `main`; without one the program fails to link.
            let entry = needsMainImageEntry(code)
                ? "\n/*snippet-glsl-main*/\nvoid main() { mainImage(fragColor, gl_FragCoord.xy); }"
                : ""
            fragment = """
            #version 300 es
            ...header lines unchanged...
            \(code)\(entry)
            """
        }
```

**Verify**: focused tests command → `** TEST SUCCEEDED **` (the three new
tests and every existing GLSL and linked-GLSL test).

### Step 4: Runtime check (only if you can launch the app)

Use the `verify` skill if it is available. Otherwise build and run the app,
create a snippet with the Shadertoy shader from "Why this matters", and open
its preview.

**Expected**: a gradient renders, and the preview console shows no "missing
main" or compile error.

If the compile log reports a redefinition of `fragColor` (the user's
`mainImage` parameter shadowing the header's global `out vec4 fragColor`),
STOP and report. GLSL ES 3.00 allows a parameter to hide a global, so this is
not expected.

If you cannot launch the app, write in your report that step 4 was not run.

### Step 5: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`.

## Test plan

- Three new tests (step 1): a Shadertoy shader gets the entry point; a shader
  with its own `main` gets none; a commented-out `main` doesn't suppress it.
- Existing GLSL tests (`test_glsl_*`, `test_linked_glslEntry_*`) must pass unchanged.

## Done criteria

- [ ] `grep -n "needsMainImageEntry" Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` → definition plus one use
- [ ] `grep -n "uniform vec2 iResolution" Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift` → still present (not changed to vec3)
- [ ] Full tests → `** TEST SUCCEEDED **`
- [ ] Step 4 done, or explicitly reported as not run
- [ ] `plans/README.md` status row updated

## STOP conditions

- `glslDocument` no longer has the header branch shown in "Current state".
- Step 4 shows a link or compile error that mentions `fragColor` or `main`.
- An existing GLSL test fails because its fixture defines `mainImage` without
  `main` and asserted the old output. Report it rather than editing the test.

## Maintenance notes

- Error line numbers in the preview console were already offset by the
  header's 7 lines; the new entry point comes after the user's code, so it
  doesn't shift them further.
- If `iResolution` is ever changed to `vec3` for Shadertoy fidelity, existing
  snippets that divide a `vec2` by it will break. That needs a migration or a
  per-snippet compatibility choice.
- Linked GLSL helpers are concatenated before the entry, so a helper that
  defines `main` correctly suppresses the wrapper.
