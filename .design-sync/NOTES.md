# design-sync notes — Snippets

## Setup

- The design system (`Sources/Snippets/DesignSystem/`) is native SwiftUI — no
  JS/React build exists in this repo by default. `web/design-system/` is a
  hand-ported React+CSS mirror built specifically so this sync could run
  (see `web/design-system/README.md`). It is not the app's real UI layer;
  keep it in sync with the Swift sources by hand if either changes.
- Node.js has no system install on this machine (no Homebrew either). A
  user-local Node v24.18.0 was installed to `~/.local/opt/node-v24.18.0-darwin-arm64`
  with `node`/`npm`/`npx` symlinked into `~/.local/bin` (already on PATH) —
  no sudo used. Re-syncs on this machine don't need to repeat that; a fresh
  machine will.
- `cfg.componentSrcMap` excludes `Color` and `DSToken` — both are plain token
  objects (not components) that the package-shape detector picked up as
  PascalCase value exports. If a future token export is added to
  `src/tokens/`, exclude it here too or it'll show up as a broken component.

## Known render warns

- `[RENDER_THIN]` on `DSIconButton`: all 4 cells are icon-only buttons (SVG,
  no text), which trips the "mounts have no text" heuristic. Screenshots
  confirm all 4 render correctly (copy/delete/star/disabled icons visible).
  Triaged as benign — expected on every future sync unless the preview
  changes.

## Font substitution (user-approved)

- The Swift app uses the system font (San Francisco). SF Pro isn't licensed
  for general web redistribution, so `--ds-font-family` was set to
  `-apple-system, BlinkMacSystemFont, system-ui, sans-serif` with no explicit
  "SF Pro" name and no shipped font files — renders as San Francisco on
  Apple devices (same as the app), platform default elsewhere. User
  confirmed this is fine; no `[FONT_MISSING]` fires because nothing
  references a family that isn't provided.

## Re-sync risks

- Color/spacing/radius/shadow/typography values in `web/design-system/src/tokens/`
  and `src/styles/tokens.css` are **hand-approximated** from the Swift
  tokens — several SwiftUI system colors (`Color.primary`, `.accentColor`,
  `NSColor.windowBackgroundColor`) don't have one fixed hex value; the
  chosen light/dark hexes are a best-effort visual match, not extracted
  programmatically. If the Swift `DesignSystem/Tokens/*.swift` files change,
  this web port must be updated by hand — nothing here detects that drift.
- `DSIconButton`'s `icon` prop is `React.ReactNode` on the web vs an SF
  Symbol name string in Swift (SF Symbols have no web renderer) — this is a
  deliberate API deviation, documented in the component's JSDoc and in
  `web/design-system/README.md`.
- `DSGlassContainer`'s native macOS 26+ glass-morph/merge behavior
  (`GlassEffectContainer`) has no CSS equivalent — the web version is a
  plain spaced flex column. Documented in the component's JSDoc.
- This is a first sync — every component was authored and graded `good`
  this run, none carried forward from a prior anchor.
