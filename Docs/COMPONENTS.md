# Component Reference

This file explains every shared component under `Sources/Snippets/Views/Components` plus important private helper components embedded in those files.

## `SnippetCard`

Path: `Sources/Snippets/Views/Components/SnippetCard.swift`

What it does:

- Gallery tile for a snippet.
- Shows title, description, code or media preview, language badge, media count, copy button, created date, and trash countdown when in trash mode.
- Handles copy-to-clipboard, hover tilt, shader overlays, and trash action dialog.

Customize it:

- Change card sizing in the preview `.frame(height: 160)` and outer padding.
- Change title/description typography in the top `VStack`.
- Change copy behavior in `performCopy()`.
- Change hover motion in the `rotation3DEffect`, `offset`, and shadow modifiers.
- Change media preview behavior in `GalleryAttachmentPreview`, `CardMediaGrid`, `CardImagePreview`, and `CardVideoPreview`.

## `CardHoverShaderOverlay` And `CardPreviewShaderOverlay`

Path: `Sources/Snippets/Views/Components/SnippetCard.swift`

What they do:

- Draw animated light/glow overlays on hovered snippet cards and preview areas.
- Use `TimelineView` so animation pauses when inactive.

Customize them:

- Change glow colors by changing the `accent.opacity(...)` values.
- Change speed with the elapsed-time multipliers and sweep duration.
- Change hover falloff by changing radial gradient radii.

## `GalleryAttachmentPreview`

Path: `Sources/Snippets/Views/Components/SnippetCard.swift`

What it does:

- Renders one media attachment inside a snippet card.
- Chooses image or video preview based on `MediaKind`.
- Adds a play badge for videos.

Customize it:

- Change padding and corner radius through `GalleryCardAttachmentLayout`.
- Change image loading in `CardImagePreview`.
- Change video playback in shared `LoopingVideoPlayerView`.

## `CardMediaGrid`

Path: `Sources/Snippets/Views/Components/SnippetCard.swift`

What it does:

- Shows up to four attachments in a 1- or 2-column grid inside a card.
- Adds a `+N` overlay when there are more than four attachments.

Customize it:

- Change maximum displayed attachments by replacing `items.prefix(4)`.
- Change spacing with the local `spacing` constant.
- Change tile sizing by editing the `tileWidth` and `tileHeight` calculation.

## `GallerySection`

Path: `Sources/Snippets/Views/Components/GallerySection.swift`

What it does:

- Reusable wrapper for collapsible gallery sections.
- Combines a `GallerySectionHeader` with animated `CollapsibleSectionContent`.
- Used by `SnippetGalleryView` for both collection and snippet sections.

Customize it:

- Change section spacing in the outer `VStack`.
- Change default animation in the initializer.
- Use it for new gallery sections by passing title, count, icon, tint, expansion binding, and content.

## `GallerySectionHeader`

Path: `Sources/Snippets/Views/Components/GallerySection.swift`

What it does:

- Glass-styled section toggle row with chevron, icon, title, count badge, and divider line.

Customize it:

- Change the count badge shape/color in the `Text("\(count)")` background.
- Change the glass styling in `.liquidGlassSurface(...)`.
- Change typography through `Sans.font` and `Mono.font`.

## `CollapsibleSectionContent`

Path: `Sources/Snippets/Views/Components/GallerySection.swift`

What it does:

- Measures its content height and animates open/closed height.
- Clips during collapse/expand to prevent visual overflow.

Customize it:

- Change animation by passing a different `Animation`.
- Change the clipping delay in the `DispatchQueue.main.asyncAfter(...)` call.
- Reuse it outside the gallery when you need a measured-height collapse.

## `LoopingVideoPlayerView`

Path: `Sources/Snippets/Views/Components/LoopingVideoPlayerView.swift`

What it does:

- Shared muted looping AVPlayer wrapper for attachment videos.
- Used by gallery cards and detail/lightbox views.
- Keeps player setup, loop observer, teardown, and layer resizing in one place.

Customize it:

- Change default scaling with `videoGravity`.
- Add playback controls by replacing the `NSViewRepresentable` implementation with an `AVPlayerView`.
- Change mute/autoplay behavior in `LoopingVideoContainerView.configure(with:videoGravity:)`.

## `LanguageBadge`

Path: `Sources/Snippets/Views/Components/LanguageBadge.swift`

What it does:

- Compact pill showing a language icon and label.
- Uses `SupportedLanguage` accent colors and supports compact sizing.
- Also defines helpful `Color` extensions for hex parsing, hex output, and color blending.

Customize it:

- Change compact/noncompact padding and font sizes in `body`.
- Change badge color intensity in `accent`.
- Add or edit language names/colors in `SupportedLanguage`.

## `SectionHeader`

Path: `Sources/Snippets/Views/Components/SectionHeader.swift`

What it does:

- Small section label used throughout editor/detail forms.
- Shows a prefix, label, divider line, and optional trailing view.

Customize it:

- Change default prefix through the initializer.
- Change label style in `body`.
- Pass `trailing: AnyView(...)` for counts, badges, or secondary labels.

## `StatusBar`

Path: `Sources/Snippets/Views/Components/StatusBar.swift`

What it does:

- Bottom bar made of icon/text segments.
- Used by the gallery/detail shell, editor, and trash.

Customize it:

- Add or remove segments where each view constructs `[StatusBar.Segment]`.
- Change spacing and padding in `StatusBar.body`.
- Change border/glass styling in the background modifier.

## `CollectionIconView`

Path: `Sources/Snippets/Views/Components/CollectionIconView.swift`

What it does:

- Renders a collection SF Symbol with a supplied color and selected state.
- Used in collection cards, editor collection chips, and collection UI.

Customize it:

- Change symbol size through the `size` parameter.
- Change selected-state rendering in `body`.
- Restrict valid symbols in `SnippetCollection.validSFSymbolName(...)`.

## `CodeEditor`

Path: `Sources/Snippets/Views/Components/CodeEditor.swift`

What it does:

- AppKit-backed editable code text view.
- Binds text/focus into SwiftUI, applies syntax highlighting, supports line numbers, and respects theme/font settings.

Customize it:

- Change editor font size with the `fontSize` argument.
- Change minimum height with `minHeight`.
- Change highlighting in `SyntaxHighlighter`.
- Change line-number behavior in `LineNumberRulerView`.

## `CodeView`

Path: `Sources/Snippets/Views/Components/CodeView.swift`

What it does:

- SwiftUI code display component for read-only code snippets.
- Can show line numbers and uses monospaced styling.

Customize it:

- Change line number display with `showLineNumbers`.
- Change typography with `fontSize`.
- Replace with `HighlightedCodeView` when syntax highlighting is required.

## `DotGridBackground`

Path: `Sources/Snippets/Views/Components/DotGridBackground.swift`

What it does:

- Draws the app's dotted background with optional gradient palette.
- Used behind main gallery, sidebar, editor, and trash.

Customize it:

- Change palette by passing `gradientPalette`.
- Change light-mode intensity with `lightModeStrength`.
- Change dot spacing, opacity, or gradient math inside the component.

## `GlassCard`

Path: `Sources/Snippets/Views/Components/GlassCard.swift`

What it does:

- Generic glass card wrapper.
- Provides the `liquidGlassSurface` view modifier used across buttons, sections, and cards.

Customize it:

- Change the default card radius/padding in `GlassCard`.
- Change all glass surfaces by editing `LiquidGlassSurfaceModifier`.
- Use `.liquidGlassSurface(in:tint:interactive:borderOpacity:shadowRadius:shadowY:)` on new controls.

## `EditorTabHeader`

Path: `Sources/Snippets/Views/Components/EditorTabHeader.swift`

What it does:

- Small editor-style tab/header component.
- Useful for code/editor chrome patterns.

Customize it:

- Change label/icon content in its initializer and body.
- Align styling with `SnippetEditorView.editorChrome` if you reuse it there.

## `ViewSnapshot`

Path: `Sources/Snippets/Views/Components/ViewSnapshot.swift`

What it does:

- Captures SwiftUI views as `NSImage`.
- Used by `SnippetGalleryView` to snapshot snippet cards before running the Metal Genie animation.

Customize it:

- Change snapshot scale/background in `snapshot(of:size:)`.
- Reuse it for other animated transitions that need a rendered image texture.

## `MetalGenieOverlay`

Path: `Sources/Snippets/Views/Components/MetalGenieOverlay.swift`

What it does:

- SwiftUI wrapper around a MetalKit view for the delete/restore Genie distortion.
- Checks whether Metal is supported and bridges SwiftUI state into `MetalGenieRenderer`.

Customize it:

- Change fallback behavior at call sites in `SnippetGalleryView`.
- Change progress/accent/snapshot inputs to support new effects.
- Change renderer setup in `MetalGenieRepresentable`.

## `MetalGenieRenderer`

Path: `Sources/Snippets/Views/Components/MetalGenieRenderer.swift`

What it does:

- Metal renderer for the Genie shader effect.
- Loads `GenieShaders.metal`, manages pipeline state, snapshot textures, uniforms, and draw calls.

Customize it:

- Change shader lookup if you move `GenieShaders.metal`.
- Change uniforms and draw timing alongside the Metal shader.
- Change logging category or fallback behavior for shader load failures.

## `GenieShaders.metal`

Path: `Sources/Snippets/Views/Components/GenieShaders.metal`

What it does:

- Metal shader source for the Genie distortion animation.
- Works with `MetalGenieRenderer`.

Customize it:

- Change the visual distortion by editing vertex/fragment shader math.
- Keep uniforms synchronized with `MetalGenieRenderer`.
- Test both supported and fallback paths after editing shader inputs.
