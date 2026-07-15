# Plan 001: Fix stale README requirements and add a repo-root CLAUDE.md with build invariants

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- README.md CLAUDE.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs / dx
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

The README says the app requires "macOS 15+", but `Package.swift` declares `platforms: [.macOS(.v26)]` — anyone following the README on macOS 15–25 hits an immediate `swift build` platform error. The README also documents `swift test` without the `DEVELOPER_DIR` prefix that is required for SwiftData macros, and there is no repo-root `CLAUDE.md`, so every agent session must rediscover the build/test invariants (Xcode-beta toolchain, dual SPM + Xcode build, the rule that new source files must be registered in the Xcode project).

## Current state

- `README.md:32` — says `- macOS 15+` under Requirements.
- `Package.swift:6-9`:
  ```swift
  // macOS 26+ so the binary is stamped with the modern SDK — AppKit only
  ...
  platforms: [.macOS(.v26)],
  ```
- `README.md:47-57` — documents `swift test` and `swift build --build-path /tmp/snippets-build` with no `DEVELOPER_DIR` mention. Line 33 already notes "SwiftData macros require the full Xcode toolchain, not the Command Line Tools alone" but the commands don't reflect it.
- No `CLAUDE.md` or `AGENTS.md` exists at the repo root (`/Users/halilbagosi/snippets`). A `CLAUDE.md` exists one directory up (`/Users/halilbagosi/CLAUDE.md`) covering only the graphify knowledge-graph workflow — do not modify it.
- Known invariants that belong in the repo CLAUDE.md (verified during the audit):
  - Build/test require the full Xcode beta toolchain:
    `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  - Tests run only via `swift test` (SPM), not the Xcode scheme.
  - Dual build system: SwiftPM (`Package.swift`) auto-discovers sources; `Snippets.xcodeproj` enumerates them manually — any new/removed/moved file under `Sources/` must also be registered in `Snippets.xcodeproj/project.pbxproj` (see commit `e017328d` "Register live preview and connection files with Xcode project").
  - Platform is macOS 26+ (Liquid Glass APIs / modern SDK stamp).
  - Keep build artifacts out of the repo: `--build-path /tmp/snippets-build` (build) and `/tmp/snippets-test-build` (test).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

(No code changes in this plan, so a build run is only a sanity check that the documented commands are accurate.)

## Scope

**In scope** (the only files you should modify/create):
- `README.md`
- `CLAUDE.md` (create, repo root)

**Out of scope** (do NOT touch):
- `/Users/halilbagosi/CLAUDE.md` (parent directory — graphify instructions, not this repo's).
- `Package.swift`, any Swift source, `Snippets.xcodeproj`.
- `Docs/` — intentionally untracked working notes.

## Git workflow

- Branch: `advisor/001-readme-and-claude-md`
- Commit style: short sentence-case imperative subject, no conventional-commit prefixes (e.g. `Document dual build system in verify skill`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Correct the README

In `README.md`:
1. Change line 32 from `- macOS 15+` to `- macOS 26+ (the app links against the macOS 26 SDK for the Liquid Glass design system)`.
2. In the Build/Test sections, prefix the documented commands with the toolchain requirement. Add above the first ```sh block:
   > SwiftData macros require the full Xcode (beta) toolchain. Point `DEVELOPER_DIR` at it before building or testing:
   and show `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` in the code block.
3. Add a short "Dual build system" note in the Build section: SwiftPM auto-discovers sources; the Xcode project lists files manually, so new source files must also be added to `Snippets.xcodeproj`.

**Verify**: `grep -n "macOS 26" README.md` → at least one match; `grep -n "macOS 15" README.md` → no matches; `grep -n "DEVELOPER_DIR" README.md` → at least one match.

### Step 2: Create repo-root CLAUDE.md

Create `CLAUDE.md` at the repo root containing (concise, ~30 lines): the build and test commands exactly as in "Current state" above; the dual-build-system registration rule; the macOS 26+ platform constraint; the source layout one-liner ("see README Project Structure"); and the note that tests must run via `swift test`, not Xcode.

**Verify**: `test -f CLAUDE.md && grep -c "DEVELOPER_DIR" CLAUDE.md` → ≥ 1.

### Step 3: Sanity-check the documented commands

Run the build command from the table. If it fails because Xcode-beta is not installed at that path, record the actual working `DEVELOPER_DIR` and use it consistently in both files.

**Verify**: build command exits 0.

## Test plan

No code changes; verification is the greps above plus one successful build with the documented command.

## Done criteria

- [ ] `grep -rn "macOS 15" README.md` returns no matches
- [ ] `README.md` and `CLAUDE.md` both mention `DEVELOPER_DIR` and the dual build system
- [ ] Documented build command exits 0 when run verbatim
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `Package.swift` no longer says `.macOS(.v26)` (requirements may have genuinely changed — the README fix would then be wrong).
- A repo-root `CLAUDE.md` already exists (merge instead of overwrite — report first).
- The documented build command fails for a reason other than a different Xcode path.

## Maintenance notes

- When the Xcode beta becomes a stable release, both files' `DEVELOPER_DIR` guidance need updating.
- Plan 007 (CI) will encode these same commands in a workflow — keep them in sync.
