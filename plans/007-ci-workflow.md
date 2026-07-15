# Plan 007: Add a CI workflow — swift test + web design-system build

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- .github/ web/design-system/package.json`
> If `.github/workflows/` already exists, reconcile with it instead of
> overwriting (STOP and report what exists).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW locally / MED that hosted runners lack the required toolchain (see STOP conditions)
- **Depends on**: 001 (documented commands), ideally 006 (a meaningful suite to run)
- **Category**: dx
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

There is no CI, lint, or formatter anywhere in the repo — no `.github/`, no `.swiftlint.yml`, no lint/test script in `web/design-system/package.json`. Nothing verifies `swift test` or the web build on push; regressions land silently, and the hand-ported React design system has no automated gate at all. One workflow running the two build/test commands is the highest-leverage verification baseline.

## Current state

- No `.github/` directory exists at repo root.
- Swift tests: 11+ files in `Tests/SnippetsTests/`, run via SwiftPM only. **Critical constraint** (from the repo's build docs / plan 001): SwiftData macros require the full Xcode toolchain and the package targets **macOS 26** (`Package.swift:9`, `platforms: [.macOS(.v26)]`), with local dev pinned to `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. GitHub-hosted macOS runners may not offer an Xcode with the macOS 26 SDK — this must be probed, not assumed.
- Web: `web/design-system/package.json` — scripts are only `build` (`tsup && node scripts/copy-css.mjs`) and `dev`; `package-lock.json` exists (so `npm ci` works); no test/lint/typecheck script. `tsup` runs a TS build but a separate `tsc --noEmit` gives real typechecking.
- Repo hosting: confirm with `git remote -v` that the origin is GitHub (`gh repo view` should succeed) before assuming GitHub Actions is the right CI.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Swift tests (local) | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |
| Web install | `npm ci` (in `web/design-system`) | exit 0 |
| Web build | `npm run build` (in `web/design-system`) | exit 0, `dist/` populated |
| Web typecheck | `npx tsc --noEmit` (in `web/design-system`) | exit 0 |
| Workflow lint | `gh workflow list` after push, or `actionlint` if installed | parses |

## Scope

**In scope**:
- `.github/workflows/ci.yml` (create)
- `web/design-system/package.json` — add `"typecheck": "tsc --noEmit"` (and optionally `"lint"` only if you also add the config — otherwise skip lint entirely)

**Out of scope**:
- swift-format/SwiftLint adoption — bigger conventions decision; note as follow-up.
- Signing, releases, artifact upload.
- Changing any Swift source or `Package.swift`.

## Git workflow

- Branch: `advisor/007-ci-workflow`
- Short sentence-case imperative commit subjects.
- Do NOT push or open a PR unless the operator instructed it (note: the workflow can only be observed running after a push — done criteria distinguish local vs. remote verification).

## Steps

### Step 1: Probe runner feasibility for the Swift job

Check GitHub's runner images (https://github.com/actions/runner-images, `macos-26` / `macos-latest` image docs) for an Xcode release containing the macOS 26 SDK. Decide:
- Available → Swift job runs on that runner with `sudo xcode-select -s <path>` or `DEVELOPER_DIR` env.
- Not available → still create the workflow, but mark the Swift job `continue-on-error: true` with a dated comment, or gate it behind a self-hosted-runner label; the web job is unconditional either way. Record the decision in the workflow file as a comment.

**Verify**: decision + evidence (image doc line) recorded as a comment at the top of `ci.yml`.

### Step 2: Write `.github/workflows/ci.yml`

Two jobs, trigger on `push` to `main` and all `pull_request`:

1. `swift-tests` (macOS runner per step 1): checkout; select Xcode; `swift test --build-path .build-ci` with `actions/cache` on `.build-ci` keyed by `Package.swift` hash.
2. `web-build` (ubuntu-latest): checkout; `actions/setup-node` (node 20, cache npm with `cache-dependency-path: web/design-system/package-lock.json`); `npm ci`, `npx tsc --noEmit`, `npm run build`, all with `working-directory: web/design-system`.

**Verify**: `actionlint .github/workflows/ci.yml` if available, else a YAML parse (`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"`) → exit 0.

### Step 3: Add the typecheck script and verify web pipeline locally

Add `"typecheck": "tsc --noEmit"` to `web/design-system/package.json` scripts, then run install/typecheck/build locally.

**Verify**: all three web commands exit 0 locally.

### Step 4: Verify the Swift command the workflow will run, locally

Run the swift test command locally exactly as the workflow encodes it (modulo `DEVELOPER_DIR` path differences — the workflow uses the runner's Xcode).

**Verify**: exit 0, all tests pass.

## Test plan

CI is itself the test infrastructure; verification is the local runs above. Full remote validation happens on first push — if the operator permits pushing the branch, watch the run with `gh run watch`; otherwise mark the plan DONE-pending-first-push in the index.

## Done criteria

- [ ] `.github/workflows/ci.yml` exists, parses, and encodes both jobs
- [ ] Step 1 feasibility decision documented in the workflow comment
- [ ] `web/design-system/package.json` has a `typecheck` script; `npm ci && npx tsc --noEmit && npm run build` exit 0 locally
- [ ] Local `swift test` exits 0
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated (note "remote run unverified" if not pushed)

## STOP conditions

- `.github/workflows/` already exists (reconcile, don't overwrite).
- `git remote -v` shows a non-GitHub origin — GitHub Actions is the wrong target; report.
- `npx tsc --noEmit` fails on the current code — fixing TS errors is out of scope; report the errors instead.
- No hosted runner can build macOS 26 at all AND the operator context forbids `continue-on-error` noise — ask rather than shipping a permanently-red job.

## Maintenance notes

- When Xcode-with-macOS-26-SDK lands on hosted runners, remove any `continue-on-error` and pin the Xcode version.
- Follow-ups deferred: SwiftLint/swift-format, a token-parity check between Swift and TS design systems (see the design-sync finding in plans/README.md) — that check belongs in this workflow once it exists.
