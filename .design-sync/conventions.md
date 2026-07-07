## Using the Snippets design system

This is a small, token-driven system (6 components) ported from a native
SwiftUI app. No provider or theme wrapper is required — just import the
stylesheet once at your app root:

```jsx
import "@snippets/design-system/styles.css";
```

Light/dark is automatic via `prefers-color-scheme`; to force a mode instead,
set `data-theme="dark"` or `data-theme="light"` on the `<html>` element.

### Styling idiom: CSS custom properties, never inline hex/px

Every visual value is a `--ds-*` custom property from `_ds/styles.css`. Build
your own layout glue (page padding, custom containers) with these tokens —
never hardcode a color, spacing, or radius value that has a token.

| Group | Tokens |
|---|---|
| Color | `--ds-color-surface`, `--ds-color-background`, `--ds-color-text-primary`, `--ds-color-text-secondary`, `--ds-color-tint`, `--ds-color-destructive` |
| Glass surface | `--ds-glass-fill`, `--ds-glass-border`, `--ds-glass-tint-opacity`, `--ds-glass-shadow` |
| Spacing | `--ds-space-xxs` (4px) `--ds-space-xs` (8px) `--ds-space-sm` (12px) `--ds-space-md` (16px) `--ds-space-lg` (24px) `--ds-space-xl` (32px) |
| Radius | `--ds-radius-xs` (4px) `--ds-radius-sm` (8px) `--ds-radius-md` (16px) `--ds-radius-lg` (22px) `--ds-radius-capsule` (999px) |
| Shadow | `--ds-shadow-radius`/`--ds-shadow-y` (standard), `--ds-shadow-liquid-radius`/`--ds-shadow-liquid-y` (glass surfaces) |
| Typography | `--ds-font-family`, and per-scale `--ds-font-<title\|title2\|title3\|headline\|subheadline\|body\|callout\|footnote\|caption\|caption2>-size`/`-weight` |

Component classes follow `ds-<name>` / `ds-<name>--<variant>` (e.g.
`.ds-button--primary`, `.ds-tag--selected`) — these are applied internally by
each component; you never write them yourself, just pass props.

### Component notes

- **`DSButton`** — full-width by default (`title`, `style`: primary/secondary/ghost/destructive, `onClick`).
- **`DSIconButton`** — `icon` takes a rendered node (an inline SVG or icon-font glyph), not an icon name — there's no built-in icon set.
- **`DSTag`** — toggle pill (`title`, `isSelected`, `onClick`); compose several in a `flex` row for filter bars.
- **`DSBadge`** — static label; pass a `color` (defaults to `Color.tint`-style text token) and the background tints itself at 20% opacity automatically.
- **`DSGlassCard`** — the signature surface: blur + translucent fill/border. Needs a colorful/textured backdrop behind it to read as "glass" — on a flat white page it looks like a plain bordered card.
- **`DSGlassContainer`** — a spaced flex column for grouping `DSGlassCard`s; `spacing` is a raw pixel number, not a token.

### Where the truth lives

Read `_ds/styles.css` (and its `tokens.css`/`components.css` imports) before
styling anything custom, and each component's own `.prompt.md` for full prop
docs and usage examples.

### Example composition

```jsx
import { DSGlassCard, DSBadge, DSButton, Color } from "@snippets/design-system";

function SnippetCard({ title, language, code }) {
  return (
    <DSGlassCard tint={Color.tint}>
      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <strong>{title}</strong>
        <DSBadge text={language} color={Color.tint} />
      </div>
      <pre style={{ fontFamily: "monospace", fontSize: 12 }}>{code}</pre>
      <DSButton title="Copy" style="secondary" onClick={() => {}} />
    </DSGlassCard>
  );
}
```
