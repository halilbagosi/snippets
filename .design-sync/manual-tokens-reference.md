# Snippets Design System — manual reference (not a design-sync)

> **This is not a real design-sync.** Claude Design's design agent renders React
> components from a compiled JS bundle; this repo's design system
> (`Sources/Snippets/DesignSystem/`) is native SwiftUI with no JS/React
> equivalent, so there is no build artifact the sync tooling can upload or
> render. This file is a hand-written summary of the token values and
> component behavior, useful as background reading for a design agent or a
> human — it does not give the agent real, renderable components, and no
> project was created or uploaded to on claude.ai/design.

## Colors (`DSToken.Color`, `Sources/.../Tokens/DSColor.swift`)

| Token | Value |
|---|---|
| `surface` | `white` at 10% opacity |
| `background` | platform window/system background (`NSColor.windowBackgroundColor` on macOS, `UIColor.systemBackground` on iOS) |
| `textPrimary` | `Color.primary` |
| `textSecondary` | `Color.secondary` |
| `tint` | `Color.accentColor` |
| `destructive` | `Color.red` |

**Liquid Glass sub-tokens** (`DSToken.Color.LiquidGlass`) — all functions of `isDark`:

| Token | Light | Dark |
|---|---|---|
| `fill(isDark:)` | white @ 16% | white @ 3.5% |
| `border(isDark:)` | white @ 42% | white @ 18% |
| `tintFill(tint:isDark:)` | tint @ 7% | tint @ 10% |
| `shadow(isDark:)` | black @ 10% | black @ 24% |

## Spacing (`DSToken.Spacing`)

`xxs: 4, xs: 8, sm: 12, md: 16, lg: 24, xl: 32` (points)

## Radius (`DSToken.Radius`)

`xs: 4, sm: 8, md: 16, lg: 22, capsule: 999` (points)

## Shadow (`DSToken.Shadow`)

`radius: 18, y: 12` — standard drop shadow
`liquidRadius: 14, liquidY: 8` — glass-surface shadow (used by the glass modifier below)

## Typography (`DSToken.Typography`)

Maps 1:1 to the SwiftUI system font scale — no custom font family or sizes:
`title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2`.

## Components (`Sources/.../DesignSystem/Components/`)

- **DSButton** — `title`, `style` (`primary` / `secondary` / `ghost` / `destructive`), `action`. Full-width, `md` radius, `body` font, horizontal `md` / vertical `sm` padding. `primary`/`destructive` use solid fill with white text; `secondary` is `surface` fill with a 20%-opacity border; `ghost` is transparent. Dims to 50% opacity when disabled.
- **DSIconButton** — SF Symbol icon button, `sm` padding, `md` radius, fills with `surface` color on hover, dims to 50% when disabled.
- **DSTag** — toggle-style pill: `caption` font, `sm` radius, selected state inverts to `textPrimary` fill / `background` text; unselected has a `textSecondary` 1pt border.
- **DSBadge** — small static label, `caption2` font, tinted background (20% opacity of the given color) and matching text color, `xs` radius.
- **DSGlassCard** — wraps content in `md` padding + the Liquid Glass surface modifier (see below), `md` corner radius.
- **DSGlassContainer** — thin wrapper around `GlassEffectContainer` on macOS 26+, falls through to plain content on older OS.

## Liquid Glass modifier (`Sources/.../Modifiers/DSGlassModifier.swift`)

The system's signature surface treatment, used by `DSGlassCard` and other glass surfaces:

- On macOS 26+: uses the real `glassEffect` API (`.regular` or `.regular.interactive()`).
- Fallback (older OS): `.ultraThinMaterial` background.
- Both paths layer the same overlays: a `LiquidGlass.fill` tint, an optional `LiquidGlass.tintFill` when a tint color is passed, a 1pt white border at `LiquidGlass.border` opacity, and a soft shadow (`LiquidGlass.shadow` color, `Shadow.liquidRadius`/`liquidY`).
- `liquidGlassBar(divider:)` is a separate, darker-tinted variant for window-chrome strips (search headers, status bars) — mirrors Xcode/Finder's bottom bar treatment, with an optional hairline divider on the top or bottom edge.

## Not covered here

Component prop APIs beyond what's listed, other views under `Sources/Snippets/Features/`, and any layout/composition conventions. Read the source files directly for anything beyond this summary — this file is not kept in sync automatically.
