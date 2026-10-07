# Plan 023: Stop the language detector from confidently mislabeling Java, C#, PHP, Swift and commented Python

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Services/LanguageDetector.swift Sources/Snippets/Services/LanguageDetectorRules.swift Tests/SnippetsTests/LanguageDetectorHardeningTests.swift`
> (includes uncommitted edits). Plan 019 adds `init(stored:)` near the top of
> `LanguageDetector.swift`; that change is expected. Any change to the
> sanitizer or the rules is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW–MED (detection drives highlighting and which preview engine runs)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

The detector (weighted regex evidence per language, highest score wins) is
well designed, but it mislabels common code with confidence. These are
measured results from the current code:

| Input | Detected today | Should be |
|---|---|---|
| Java class with `public static void main` / `System.out.println` | **Swift** | Unknown (not supported) |
| C# class with `using System;` / `{ get; set; }` | **Swift** | Unknown |
| PHP with `<?php`, `function greet($name)` | **JavaScript** | Unknown |
| `struct Point {\n  var x: Double\n  var y: Double\n}` | **Kotlin** | Swift |
| `let x = [1, 2, 3].map { $0 * 2 }` | Unknown | Swift |
| Python whose `# comments` quote JSX/DOM code | **React** | not React |

A wrong label is worse than "Unknown". Java detected as Swift is sent to the
**Swift preview compiler**, and PHP detected as JavaScript runs in the web
preview.

There are three causes:

1. **No profiles for unsupported languages.** Their code is scored only by
   the supported profiles, and the closest one wins.
2. **The sanitizer strips `//` and `/* */` comments, but not `#` comments.**
   Python, shell and Ruby comments therefore count as evidence.
3. **Kotlin and Swift lack negative evidence.** Kotlin has no `struct`, and
   Swift has no `fun` or `val`.

The fix below was prototyped against a copy of the detector. It fixes every
row above and still passes all 62 existing tests in
`LanguageDetectorTests`, `LanguageDetectorCorpusTests` and
`LanguageDetectorHardeningTests`.

## Current state

- `Sources/Snippets/Services/LanguageDetector.swift` — the algorithm:
  - `detect(code:)` → fences → JSON → `sanitized(_:)` → `scores(for:)` → `resolve(_:)`.
  - `Profile(language:markers:penalties:)` takes a language, its markers, and
    optional penalties (subtracted).
  - `resolve` returns `.unknown` when the winner's language is `.unknown`
    (`guard winner != .unknown else { return .unknown }`, line 222). The tie
    priority of `.unknown` is `.max`, so it never wins a tie.
- `Sources/Snippets/Services/LanguageDetectorRules.swift` — the evidence tables;
  `profiles` concatenates `shaderProfiles, appleProfiles, systemsProfiles, webProfiles`
  (lines 22-27). The CSS profile (lines 237-253) is the existing example of
  `penalties:`.

`LanguageDetector.swift:377-402` (the comment-handling part of `sanitized`):
```swift
            if byte == .backtick {
                result.append(contentsOf: [UInt8.backtick, .backtick])
                index = endOfTemplate(bytes, from: index + 1)
                continue
            }

            if byte == .slash, index + 1 < bytes.count {
                if bytes[index + 1] == .slash {
                    while index < bytes.count, bytes[index] != .newline { index += 1 }
                    continue
                }
```

`LanguageDetector.swift:453-462` (byte constants):
```swift
private extension UInt8 {
    static let quote: UInt8 = 0x22
    ...
    static let newline: UInt8 = 0x0A
    static let space: UInt8 = 0x20
}
```

`LanguageDetectorRules.swift:89-93` (end of the Swift profile) and `:105-108`
(end of the Kotlin profile):
```swift
                marker(#"->\s*(Void|Self|Never)\b|\(\s*\)\s*->"#, Weight.medium, cap: 2),
                marker(#"\bself\.\w"#, Weight.weak, cap: 2)
            ]),
```
```swift
                marker(#"\bprintln\s*\(|\bwhen\s*[({]"#, Weight.medium, cap: 2)
            ])
        ]
    }
```

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Detector tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/LanguageDetectorTests -only-testing:SnippetsTests/LanguageDetectorCorpusTests -only-testing:SnippetsTests/LanguageDetectorHardeningTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Scope

**In scope**:
- `Sources/Snippets/Services/LanguageDetector.swift` — the `sanitized` loop and the `UInt8` constants only
- `Sources/Snippets/Services/LanguageDetectorRules.swift`
- `Tests/SnippetsTests/LanguageDetectorHardeningTests.swift`

**Out of scope** (do NOT touch):
- `SupportedLanguage` (the enum) — no new languages in this plan. Real
  support for Java, Bash and the rest is a separate product decision (it
  needs highlighting rules, icons and colors).
- `resolve`, weights, `minimumConfidence`, `scanLimit`.
- Existing tests — none should need changes. If one does, that is a STOP condition.
- `SyntaxHighlighter.swift` (it has the owner's uncommitted work).

## Git workflow

- Branch: `advisor/023-language-detector-misfires`
- Commit message: `Keep the language detector from mislabeling unsupported and commented code`
- `git add` the three in-scope paths only. Do NOT push unless instructed.

## Steps

### Step 1: Failing tests

Add to `LanguageDetectorHardeningTests.swift`. Put the misfire cases in the
existing `// MARK: Unsupported languages must not claim a preview engine`
section, and the rest in a new `// MARK: Misfires fixed in plan 023` section:

```swift
    func test_javaClass_isUnknown() {
        let code = "public class Main {\n    public static void main(String[] args) {\n        List<String> names = new ArrayList<>();\n        System.out.println(\"Hello\");\n    }\n}"
        XCTAssertEqual(LanguageDetector.detect(code: code), .unknown)
    }

    func test_javaServiceWithoutMain_isUnknown() {
        let code = "@Service\npublic class UserService {\n    private final UserRepository repo;\n    public List<User> findAll() {\n        return repo.findAll();\n    }\n}"
        XCTAssertEqual(LanguageDetector.detect(code: code), .unknown)
    }

    func test_csharpClass_isUnknown() {
        let code = "using System;\nusing System.Linq;\nnamespace App {\n    public class Greeter {\n        public string Name { get; set; }\n        public void Greet() => Console.WriteLine($\"Hi {Name}\");\n    }\n}"
        XCTAssertEqual(LanguageDetector.detect(code: code), .unknown)
    }

    func test_php_isUnknown() {
        XCTAssertEqual(LanguageDetector.detect(code: "<?php\nfunction greet($name) {\n    echo \"Hello, \" . $name;\n}\n$items = array_map(fn($x) => $x * 2, $list);"), .unknown)
        XCTAssertEqual(LanguageDetector.detect(code: "function greet($name) {\n    return \"Hello \" . $name;\n}\n$user->save();"), .unknown)
    }

    // MARK: Misfires fixed in plan 023

    func test_swiftStructWithTypedProperties_detectsSwift() {
        XCTAssertEqual(LanguageDetector.detect(code: "struct Point {\n  var x: Double\n  var y: Double\n}"), .swift)
    }

    func test_swiftClosureShorthand_detectsSwift() {
        XCTAssertEqual(LanguageDetector.detect(code: "let x = [1, 2, 3].map { $0 * 2 }"), .swift)
    }

    func test_pythonHashCommentsQuotingJSX_doNotDetectReact() {
        let code = "# const x = () => { console.log(document.querySelector('a')) }\n# export default function App() { return <div className=\"x\"/> }\nx = 1\nprint(x)"
        XCTAssertNotEqual(LanguageDetector.detect(code: code), .react)
        XCTAssertNotEqual(LanguageDetector.detect(code: code), .javascript)
    }

    // Controls: things the new rules must not disturb.
    func test_kotlinPrivateFun_staysKotlin() {
        XCTAssertEqual(LanguageDetector.detect(code: "class Repo {\n    private fun load(id: Int): User? {\n        return cache[id]\n    }\n}"), .kotlin)
    }

    func test_cssIdSelector_staysCSS() {
        XCTAssertEqual(LanguageDetector.detect(code: "#header {\n  color: red;\n}\n.nav a:hover { color: blue; }"), .css)
    }

    func test_jQueryDollarAssignments_stayJavaScript() {
        XCTAssertEqual(LanguageDetector.detect(code: "$(function() {\n  $el = $('#x');\n  $el.on('click', () => console.log('hi'));\n});"), .javascript)
    }

    func test_pythonInlineHashComment_staysPython() {
        XCTAssertEqual(LanguageDetector.detect(code: "def add(a, b):  # returns sum\n    return a + b"), .python)
    }

    func test_swiftPublicAsyncFunc_staysSwift() {
        XCTAssertEqual(LanguageDetector.detect(code: "public struct Api {\n    public func fetch(_ id: Int) async throws -> User {\n        try await client.get(id)\n    }\n}"), .swift)
    }
```

**Verify**: detector tests command → `** TEST FAILED **`. The failures are
exactly: `test_javaClass_isUnknown`, `test_javaServiceWithoutMain_isUnknown`,
`test_csharpClass_isUnknown`,
`test_php_isUnknown`, `test_swiftStructWithTypedProperties_detectsSwift`,
`test_swiftClosureShorthand_detectsSwift` and
`test_pythonHashCommentsQuotingJSX_doNotDetectReact`. All control tests pass.

### Step 2: Strip `#` comments in the sanitizer

In `LanguageDetector.swift`, add two constants to the `private extension UInt8`:

```swift
    static let hash: UInt8 = 0x23
    static let tab: UInt8 = 0x09
```

In `sanitized(_:)`, insert this block directly **before**
`if byte == .slash, index + 1 < bytes.count {`:

```swift
            // `#` comments (Python, shell, Ruby, YAML): a `#` followed by a
            // space or the end of the line, at a line start or after
            // whitespace. `#include`, `#version`, `#[derive]`, `#!` and
            // `#Preview` have no space after the `#` and survive.
            if byte == .hash,
               index + 1 == bytes.count || bytes[index + 1] == .space || bytes[index + 1] == .tab || bytes[index + 1] == .newline,
               index == 0 || bytes[index - 1] == .space || bytes[index - 1] == .tab || bytes[index - 1] == .newline {
                while index < bytes.count, bytes[index] != .newline { index += 1 }
                continue
            }
```

**Verify**: detector tests command → `test_pythonHashCommentsQuotingJSX_doNotDetectReact`
now passes, and no test that passed in step 1 fails.

### Step 3: Negative and extra evidence for Swift and Kotlin

In `LanguageDetectorRules.swift`:

1. In the Swift profile, replace the last marker line
   `marker(#"\bself\.\w"#, Weight.weak, cap: 2)` and the closing `]),` with:

```swift
                marker(#"\bself\.\w"#, Weight.weak, cap: 2),
                // Closure shorthand arguments: `{ $0 * 2 }`.
                marker(#"\{\s*\$\d"#, Weight.strong, cap: 2),
                // A stored property with a type and no initializer or `;` —
                // invalid in Kotlin class bodies, absent from TS (no `var`).
                marker(#"(?m)^\s*(var|let)\s+\w+\s*:\s*[A-Z][\w<>\[\], ]*[?!]?\s*$"#, Weight.strong, cap: 2)
            ], penalties: [
                // Kotlin-only keywords.
                marker(#"\bfun\s+\w|\bval\s+\w"#, Weight.decisive, cap: 1)
            ]),
```

2. In the Kotlin profile, change its closing `])` (after the `println` marker) to:

```swift
            ], penalties: [
                // Swift-only declarations; Kotlin has no struct, extension,
                // protocol, guard or func.
                marker(#"(?m)^\s*((public|private|internal|fileprivate)\s+)?(struct|extension|protocol|guard)\b|\bfunc\s+\w"#, Weight.decisive, cap: 1)
            ])
```

**Verify**: detector tests command → the two Swift tests now pass; nothing
that passed earlier fails.

### Step 4: Decoy profiles for unsupported languages

In `LanguageDetectorRules.swift`:

1. Change `profiles` to include a fifth group:

```swift
    static let profiles: [Profile] = [
        shaderProfiles,
        appleProfiles,
        systemsProfiles,
        webProfiles,
        unsupportedProfiles
    ].flatMap { $0 }
```

2. Add this section directly above `// MARK: - Shared pieces`:

```swift
    // MARK: - Unsupported (decoys)

    /// Languages the app doesn't support still need a profile: without one,
    /// their code is scored only by the supported profiles and the nearest
    /// lookalike wins (Java read as Swift and sent to the Swift preview
    /// compiler). A decoy that wins resolves to `.unknown`.
    private static var unsupportedProfiles: [Profile] {
        [
            // Java
            Profile(language: .unknown, markers: [
                marker(#"\bSystem\.(out|err)\.print"#, Weight.decisive),
                marker(#"\bpublic\s+static\s+void\s+main\s*\("#, Weight.decisive),
                marker(#"\bString\[\]\s+\w"#, Weight.decisive),
                // `public List<User> findAll() {` — modifier, type, name, params, brace.
                // The lookahead keeps Kotlin `fun`, Swift `func`/`var`/`init`
                // and TS `async` methods out.
                marker(#"(?m)^\s*(public|private|protected)\s+(static\s+)?(final\s+)?(?!fun\b|func\b|function\b|fn\b|def\b|class\b|interface\b|enum\b|var\b|let\b|val\b|init\b|async\b)[A-Za-z_][\w.]*(<[^>\n]*>)?(\[\])?\s+\w+\s*\([^)\n]*\)\s*(throws\s+[\w., ]+)?\s*\{"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*(private|public|protected)\s+(static\s+)?final\s+\w+(<[^>\n]*>)?\s+\w+\s*[;=]"#, Weight.strong, cap: 2),
                marker(#"@Override\b|\b(ArrayList|HashMap|HashSet)\s*<"#, Weight.strong, cap: 2)
            ]),
            // C#
            Profile(language: .unknown, markers: [
                marker(#"(?m)^\s*using\s+System(\.[\w.]+)?\s*;"#, Weight.decisive),
                marker(#"\{\s*get;\s*(set;|init;)?\s*\}"#, Weight.decisive, cap: 2),
                marker(#"\bConsole\.Write(Line)?\s*\("#, Weight.decisive),
                marker(#"\basync\s+Task\b|\bTask<"#, Weight.strong)
            ]),
            // PHP
            Profile(language: .unknown, markers: [
                marker(#"<\?php\b"#, Weight.decisive),
                marker(#"\bfunction\s+\w+\s*\(\s*(\??\w+\s+)?\$\w"#, Weight.decisive),
                marker(#"(?m)^\s*\$\w+\s*(\[[^\]\n]*\])?\s*=[^=>]"#, Weight.strong, cap: 2),
                marker(#"\$\w+->\w"#, Weight.strong, cap: 2)
            ])
        ]
    }
```

**Verify**: detector tests command → `** TEST SUCCEEDED **`. That covers every
new test and every existing test, 62 existing plus 12 new.

### Step 5: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`. Other suites use the
detector indirectly: `ClipboardCaptureTests`, `SnippetEditorViewModelTests`,
and the preview tests.

## Test plan

- Twelve new tests (step 1): seven misfires and five controls, plus the
  existing 62 detector tests as the regression net.
- Model new tests after the existing `test_*_isNotPreviewable` and
  `test_pythonWithCommentQuotingJavaScript_detectsPython` cases in the same file.

## Done criteria

- [ ] `grep -n "unsupportedProfiles" Sources/Snippets/Services/LanguageDetectorRules.swift` → 2 matches
- [ ] `grep -n "static let hash" Sources/Snippets/Services/LanguageDetector.swift` → 1 match
- [ ] Detector tests and full tests → `** TEST SUCCEEDED **`
- [ ] No existing test was modified (`git diff Tests/` shows only additions)
- [ ] `plans/README.md` status row updated

## STOP conditions

- An **existing** detector test fails after any step. The prototype passed
  all 62, so a failure means the code drifted or a pattern was mistyped.
  Compare against this plan character by character before anything else, and
  do not weaken a pattern or edit the old test to get green.
- A new test still fails after its step, and the cause is not a typo. Report
  the actual detection result.
- The `typicalSnippetDetectsWithinAFrame` timing test fails. Three profiles
  and three markers were added, and the prototype showed no measurable change;
  report the timing if it fails.

## Maintenance notes

- Decoys are the first step toward real support for these languages. To add
  one, give it a `SupportedLanguage` case, highlighting rules, an icon and a
  color, then move its decoy profile into the real tables with that language.
- The `#`-comment rule needs a space after `#`. A C preprocessor line written
  as `# define X` (legal but rare) is now treated as a comment.
- Small known gap, not fixed here: the React marker `\{\s*/\*` can never
  match, because the sanitizer replaces `/* */` comments before scoring. It
  is harmless dead weight.
- The Swift penalty `\bval\s+\w` would fire on a Swift identifier named `val`
  followed by another word, which is unusual but possible.
