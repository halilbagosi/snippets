# Plan 008: Remove the dead DesignSystem components (or consciously adopt them)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/DesignSystem/Components/`
> On any change, re-run the usage check in Step 1 before deleting anything.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (deleting verified-unreferenced code; build is the proof)
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

`Sources/Snippets/DesignSystem/Components/` presents itself as the app's official component library, but five of its six components — `DSButton`, `DSBadge`, `DSTag`, `DSIconButton`, `DSGlassCard` — have **zero references outside their own directory** (verified at planning time: a repo-wide grep for their names outside `DesignSystem/Components` returns nothing). The app instead renders its own parallel widgets (`Views/Components/FilterTag.swift`, `LanguageBadge.swift`, `Views/Components/GlassCard.swift`). Only `DSGlassContainer` is actually used (3 views). This misleads every design change toward the wrong (unused) files — and misleads the React port under `web/design-system/`, which mirrors these very components.

The decision (made by the maintainer via plan selection): **delete the dead components** rather than migrate the app onto them. The React port keeps its components — it serves the external Claude Design workflow, not the app.

## Current state

- Dead (to delete): `Sources/Snippets/DesignSystem/Components/DSButton.swift`, `DSBadge.swift`, `DSTag.swift`, `DSIconButton.swift`, `DSGlassCard.swift`.
- Alive (keep): `Sources/Snippets/DesignSystem/Components/DSGlassContainer.swift` (used in 3 views), everything under `DesignSystem/Tokens/` and `DesignSystem/Modifiers/` (tokens/modifiers are used broadly — do NOT delete).
- The dual build system means each deleted file must also be de-registered from `Snippets.xcodeproj/project.pbxproj` (SwiftPM auto-discovers; the Xcode project lists files manually — see commit `e017328d` for how files were registered).
- `.design-sync/manual-tokens-reference.md` documents the design system for the React port; check whether it names the deleted components and update its component list if so.
- The React port (`web/design-system/src/components/DSButton.tsx` etc.) is OUT of scope — it stays.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Usage check | `grep -rn "DSButton\|DSBadge\|DSTag\|DSIconButton\|DSGlassCard" Sources Tests --include='*.swift' \| grep -v "DesignSystem/Components"` | no output |
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope**:
- Delete: the five component files listed above
- `Snippets.xcodeproj/project.pbxproj` — remove the five files' build-file and file-reference entries
- `.design-sync/manual-tokens-reference.md` — update only if it lists the deleted components

**Out of scope**:
- `DSGlassContainer.swift`, all of `DesignSystem/Tokens/` and `DesignSystem/Modifiers/`
- `web/design-system/` — the React port keeps its components
- Migrating `FilterTag`/`LanguageBadge`/`GlassCard` onto DS components (the rejected alternative)

## Git workflow

- Branch: `advisor/008-dead-design-system-components`
- One commit; short sentence-case imperative subject.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Re-verify the components are unreferenced

Run the usage-check command. It must produce no output. (Watch for false negatives: also grep for the bare type names in `.swift` files in case of `typealias`es.)

**Verify**: usage-check command → empty output.

### Step 2: Delete the five files and de-register them from the Xcode project

`git rm` the five files. In `Snippets.xcodeproj/project.pbxproj`, remove each file's `PBXBuildFile` entry, `PBXFileReference` entry, its line in the group's `children`, and its line in the target's `Sources` build phase (grep the pbxproj for each filename; each appears ~4 times).

**Verify**: `grep -c "DSButton" Snippets.xcodeproj/project.pbxproj` → 0 (repeat per file); build → exit 0.

### Step 3: Update the design-sync doc if needed, run tests

**Verify**: test command → all pass; `grep -rn "DSButton\b" Sources` → no matches.

## Test plan

No new tests — the build succeeding after deletion is the proof of deadness. Full suite must stay green.

## Done criteria

- [ ] The five files no longer exist; `DSGlassContainer.swift`, Tokens, Modifiers untouched
- [ ] `grep -c "DSBadge\|DSButton\|DSTag\|DSIconButton\|DSGlassCard" Snippets.xcodeproj/project.pbxproj` → 0
- [ ] Build and full test suite exit 0
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Step 1's usage check produces output — a component gained a caller since planning; report which and stop.
- Deleting breaks the build with an error naming a file outside the five (hidden coupling) — report.
- The pbxproj structure doesn't match the described entry pattern (Xcode 16+ `PBXFileSystemSynchronizedRootGroup` may auto-sync, in which case no de-registration is needed — verify by grepping for the filenames first; if absent, skip step 2's pbxproj edits and note it).

## Maintenance notes

- If the app later wants a real component library, resurrect from git history and migrate `FilterTag`/`LanguageBadge`/`GlassCard` onto it in one deliberate pass — don't re-accrete a parallel set.
- The React port now has components with no Swift counterpart; the design-sync doc is the only bridge. The token-parity follow-up (see plans/README.md) is unaffected — tokens survive this plan.
