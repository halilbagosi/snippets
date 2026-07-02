# Settings window redesign & disintegration smoothness — Design

## Context

Two surfaces lag behind the app's established Liquid Glass design language and polish bar:

1. **Settings window** ([SettingsView.swift](../../../Sources/Snippets/Views/Settings/SettingsView.swift)) — a stock `TabView` toolbar-tab window with `.formStyle(.grouped)` panes. It renders the OS's opaque preferences chrome and grouped-form background, which clashes with the app's de-chromed glass modals (Move-to card, Collection editor). The app targets macOS 26 minimum, so the real `glassEffect` API is always available.
2. **Delete disintegration effect** ([MetalDisintegrationRenderer.swift](../../../Sources/Snippets/Views/Components/MetalDisintegrationRenderer.swift), [DisintegrationShaders.metal.txt](../../../Sources/Snippets/Views/Components/DisintegrationShaders.metal.txt), driver in [SnippetGalleryView.swift](../../../Sources/Snippets/Views/SnippetGalleryView.swift)) — reads as choppy and unnatural.

## Root causes of the choppiness

- **Frame delivery is coupled to SwiftUI.** A `TimelineView(.animation(minimumInterval: 1/60))` ticks SwiftUI, which diffs the view tree, calls `updateNSView`, and marks the `MTKView` dirty. Ticks are not v-synced with the view's display link, are capped at 60 Hz on 120 Hz displays, and get delayed by main-thread layout work — which is guaranteed here, because the deletion triggers a grid reflow at the same moment.
- **Particle identity is unstable.** `cellSize` is a function of `progress`, so `floor(position / cellSize)` re-bins every pixel into different cells frame-over-frame: particles visibly reshuffle mid-flight.
- **Per-frame random flicker.** The ember term hashes `floor(samplePosition / 3.0)` — a coordinate that moves every frame — producing high-frequency sparkle noise.
- **High-frequency flutter.** `sin(progress * 18.0 + …)` wiggles particles ~3 fast cycles over the 1 s life, reading as jitter rather than drift.

## Approaches considered

**Settings:** (A) keep the native `TabView` and restyle only pane content — rejected: retains the opaque system toolbar/form chrome the app has been systematically removing; (B) fully custom de-chromed glass window mirroring `CollectionEditorSheet`'s recipe — chosen; (C) System Settings-style sidebar+detail — rejected, overkill for two panes.

**Animation:** (A) tune the TimelineView (120 fps, no minimum interval) — rejected: still couples Metal to SwiftUI diffing and main-thread hitches; (B) self-clocked `MTKView` (display-link driven) plus a shader rework for stable particle identity and per-particle local-time motion — chosen; (C) replace Metal with SwiftUI `Canvas` particles — rejected: loses per-pixel dissolve fidelity.

## 1. Settings window

Rewrite `SettingsView` as a fixed-size (520 × 560) de-chromed glass window, no `TabView`, no `Form`:

- **Window chrome:** a `SettingsWindowConfigurator` (`NSViewRepresentable`, same pattern as `WindowChromeConfigurator`) sets `titlebarAppearsTransparent`, hides the title, and inserts `.fullSizeContentView` so content extends under the titlebar. Traffic lights stay.
- **Background:** `DotGridBackground(gradientPalette: [accent], lightModeStrength: 0.5)` at ~0.10–0.12 opacity over the theme canvas — same recipe as `CollectionEditorSheet`.
- **Header row** (in the titlebar strip, clear of the traffic lights): a centered glass capsule tab switcher — Appearance / About pills with icon + label, the selected pill an accent-tinted glass surface sliding between tabs via `matchedGeometryEffect` with the app's standard spring.
- **Panes** switch with a subtle opacity + scale transition inside a `ScrollView` + `DSGlassContainer(spacing: 20)`.

**Appearance pane** — three glass cards (`liquidGlassSurface(in: RoundedRectangle(cornerRadius: 16), shadowRadius: 12, shadowY: 6)`, internal 12 pt-semibold-rounded uppercase section labels, matching the Collection editor):

1. **Appearance** — System / Light / Dark selected via mini window-mock preview tiles (the macOS System Settings idiom): each tile draws the theme canvas, a tiny glass card and accent dot; the System tile is split diagonally light/dark. Selection = accent ring, spring-animated.
2. **Behavior** — the two existing toggles as icon-chip rows (icon in a small accent-tinted glass chip, title + always-visible caption instead of hover-only `.help`), native `Toggle(.switch)` tinted with the accent, hairline divider between rows.
3. **Accent color** — the eight preset swatches (enlarged to 24 pt, existing ring + glow selection), plus the custom `ColorPicker` behind the same rainbow-ring affordance used in the Collection editor's color strip.

**About pane** — same content, restyled: centered app icon over a soft accent glow, rounded-design name, version, author line, inside a glass card.

`AppearanceSettings` is unchanged — this is presentation only.

## 2. Disintegration smoothness

**Driver (SnippetGalleryView):** drop the `TimelineView`; the overlay ForEach becomes static per effect. Duration 1.15 s (cleanup delay follows it).

**Renderer:** self-clocked. `isPaused = false`, `enableSetNeedsDisplay = false`, `preferredFramesPerSecond = 120`. A `beginAnimation(startDate:duration:)` call (idempotent per start date) converts the wall-clock start to `CACurrentMediaTime()`; `draw(in:)` computes eased progress per display-link callback, fully decoupled from SwiftUI. When progress reaches 1 the renderer pauses its view. A `fixedProgress` path retains support for static previews.

**Shader rework** (same entry points, rewritten fragment body):

- Fixed `cellSize = 3.0` — stable particle identity for the whole animation.
- Per-particle local time `t = smoothstep(order, order + 0.35, progress)` drives all motion — every particle has its own smooth 0→1 life, so the frontier sweeps while individual particles animate coherently.
- Motion = up-and-outward drift with quadratic ease-out on `t`, plus a low-frequency sway (≤ ~1 cycle per particle life, seed-randomized phase/rate) replacing the 18 Hz flutter.
- Gentler shrink (to ~0.55, eased) — the previous 0.3 magnified cross-cell sampling shimmer.
- Alpha = per-particle fade over the back half of `t` (quintic-smooth), with only a thin global tail fade as a safety net — replaces the hard `erase` cliff.
- Ember and edge-glow terms keyed to the stable cell seed, never to moving sample coordinates; accent-tinted frontier glow kept but softened.

## Files touched

| File | Change |
|---|---|
| `Views/Settings/SettingsView.swift` | Rewrite: de-chromed glass window, custom tab switcher, window configurator |
| `Views/Settings/AppearanceView.swift` | Rewrite as glass pane (scheme tiles, behavior rows, accent swatches) |
| `Views/Settings/AboutView.swift` | Restyle into glass card |
| `Views/Components/MetalDisintegrationRenderer.swift` | Self-clocked display-link rendering |
| `Views/Components/MetalDisintegrationOverlay.swift` | Pass start date/duration instead of per-frame progress |
| `Views/Components/DisintegrationShaders.metal.txt` | Fragment rework: stable cells, per-particle local time, no per-frame noise |
| `Views/SnippetGalleryView.swift` | Remove TimelineView driver; duration bump |

## Testing / verification

No UI test harness exists. Verification is `xcodebuild` compile + manual visual run (settings window in light/dark, delete a snippet and watch the dissolve, including deleting several cards rapidly).
