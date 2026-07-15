# Plan 004: Make the Swift-preview dylib cache crash-safe (atomic writes, no poisoned cache)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift`
> On any change, compare the "Current state" excerpt against the live code;
> on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

`SwiftPreviewBuilder` caches compiled snippet dylibs keyed by source hash. Cache validity is a bare `fileExists` check, and `swiftc` writes the dylib directly to its final path. If the app is killed or the compiler crashes mid-write, a truncated `.dylib` remains; every subsequent preview of that exact snippet content skips compilation, fails `dlopen`, and shows a permanent "load failed" until the user manually clears `~/Library/Caches/SnippetPreviews`. Compile to a temporary path and atomically move into place, and fall back to recompilation when `dlopen` fails on a cached artifact.

## Current state

`Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift`:

- Cache check + compile (`:76-83`):
  ```swift
  let dylibURL = cacheDirectory.appendingPathComponent("\(harness.hash).dylib")

  if !FileManager.default.fileExists(atPath: dylibURL.path) {
      try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
      let sourceURL = cacheDirectory.appendingPathComponent("\(harness.hash).swift")
      try harness.source.write(to: sourceURL, atomically: true, encoding: .utf8)
      try compile(swiftc: swiftc, source: sourceURL, output: dylibURL, hash: harness.hash)
  }

  guard let handle = dlopen(dylibURL.path, RTLD_NOW) else {
      let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
      throw BuildError.loadFailed(message)
  }
  ```
- `compile(swiftc:source:output:hash:)` (`:99-134`) runs `/usr/bin/xcrun swiftc ... -o output.path` via `Process`, checks `terminationStatus`, and throws `BuildError.compileFailed(cleaned)` with cleaned diagnostics. The dylib write is non-atomic (direct `-o`).
- Cache dir: `~/Library/Caches/.../SnippetPreviews` via `cacheDirectory` (`:~55-61`).
- Existing tests for the harness (not the builder): `Tests/SnippetsTests/SwiftPreviewHarnessTests.swift`. The builder itself invokes `swiftc`/`dlopen`, so it is only partially unit-testable; the atomic-move logic can be tested if factored as a pure-ish helper.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope**:
- `Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift`
- `Tests/SnippetsTests/SwiftPreviewBuilderTests.swift` (create, only if the helper in step 1 is cleanly testable without invoking swiftc)

**Out of scope**:
- The security architecture of in-process `dlopen` (plan 005 — a design plan; do not attempt sandboxing here).
- `SwiftPreviewHostView.swift` task-cancellation race — separate recorded finding.
- `SwiftPreviewHarness.swift`.

## Git workflow

- Branch: `advisor/004-swift-preview-dylib-cache`
- Short sentence-case imperative commit subjects.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Compile to a temp path, atomically move on success

In `build(entry:helpers:)` / `compile(...)`:

1. Change the compile output to a sibling temp path: `\(harness.hash).dylib.tmp-\(UUID().uuidString)` inside `cacheDirectory` (unique suffix so concurrent builds can't collide).
2. After `compile` returns success, `FileManager.default.moveItem` (or `replaceItemAt`) the temp file to `dylibURL`. If the destination appeared meanwhile (another build won), remove the temp file and use the existing one.
3. Wrap so the temp file is removed on any failure path (`defer` + existence check).

**Verify**: build → exit 0.

### Step 2: Recover from a poisoned cache entry

When `dlopen` fails on a dylib that came from cache (i.e. the `fileExists` branch was skipped), delete the cached file and retry the compile+load once before throwing `BuildError.loadFailed`. Simplest shape: track `usedCache: Bool`; on `dlopen == nil && usedCache`, remove `dylibURL` and recurse/loop once.

**Verify**: build → exit 0.

### Step 3: Tests (best effort)

If steps 1–2 were implemented via a small testable helper (e.g. a function taking `FileManager` + URLs), add `Tests/SnippetsTests/SwiftPreviewBuilderTests.swift` covering: temp file promoted on success; temp cleaned up on failure; poisoned-cache file removed and rebuilt (can simulate by writing a garbage `.dylib` file at the cache path and asserting the retry path deletes it — the actual recompile requires swiftc, so assert deletion only if the toolchain isn't available). If the logic stayed inline in the actor and can't be tested without invoking swiftc, skip the test file and say so in the status update — do not write a test that shells out to swiftc in CI-unsafe ways unless `SwiftToolchain.swiftcURL` resolves in the test environment (it does locally per the memory that tests run under the full Xcode toolchain; a compile-a-trivial-snippet integration test is acceptable if it runs in < ~30s).

**Verify**: test command → all pass.

## Test plan

Covered in step 3. Model the file structurally on `Tests/SnippetsTests/SwiftPreviewHarnessTests.swift`. Minimum bar if full testing is impractical: one test that plants a corrupt file at the expected cache path and asserts a subsequent `build` does not fail with `loadFailed` (i.e. the retry replaced it) — acceptable as an integration test if swiftc is available.

## Done criteria

- [ ] Build and test commands exit 0
- [ ] `grep -n "moveItem\|replaceItem" Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift` → ≥ 1 match
- [ ] The `dlopen` failure path on a cached dylib deletes the file and retries once (visible in the diff)
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- The excerpt doesn't match the live code (drift — plan 005's design work may have already restructured this file).
- The builder turns out to be an actor/class whose concurrency isolation makes the retry loop unsafe to add without broader changes.
- The integration test takes > 60s or is flaky — drop it and report rather than shipping a flaky test.

## Maintenance notes

- Plan 005 (sandboxing design) may move compilation out of process; this atomic-cache logic should move with it — it is about artifact integrity, not where the compile runs.
- Reviewer: check the concurrent-build race in step 1's "destination appeared meanwhile" handling.
