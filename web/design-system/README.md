# @snippets/design-system

React/CSS port of `Sources/Snippets/DesignSystem/` (the Snippets macOS/iOS app's
SwiftUI design system), built so it can be synced into
[Claude Design](https://claude.ai/design) via the `design-sync` skill.

Six components — `DSButton`, `DSIconButton`, `DSTag`, `DSBadge`, `DSGlassCard`,
`DSGlassContainer` — plus the five token groups (`Color`, `Spacing`, `Radius`,
`Shadow`, `Typography`) from `DSToken`. Styling is plain CSS custom properties
(`--ds-*`, see `src/styles/tokens.css`) and `ds-*` utility classes
(`src/styles/components.css`) — no CSS-in-JS, no build-time theming step.

This is a hand-ported mirror kept for design-tooling purposes, not the
app's real UI layer — the Swift sources remain the source of truth for the
actual product.

```sh
npm install
npm run build   # → dist/index.es.js, dist/index.js, dist/index.d.ts, dist/styles.css
```
