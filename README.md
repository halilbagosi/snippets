# Snippets

Snippets is a native macOS app built with SwiftUI and SwiftData for organizing, searching, and previewing code snippets. It supports collections, media attachments, language-aware filtering, live previews, a menu bar quick-copy panel, and soft-delete recovery from Trash.

## Features

- Create and edit snippets with title, description, language, code, and attachments
- Organize snippets into nested collections
- Search and filter by text, language, and collection
- Attach images and videos to snippets
- Browse snippets in a polished gallery interface built on a Liquid Glass design system
- Drive the app from Shortcuts and Siri via App Intents (create, find, copy, open, and favorite snippets)
- Recover deleted snippets from Trash before permanent cleanup
- Persist data locally using SwiftData
- Preview a snippet live: HTML, CSS, JavaScript, TypeScript, React, and GLSL in a web view, Metal shaders on the GPU, and Swift compiled and run in the app
- Connect snippets so a helper runs before the snippet that uses it, in one shared preview
- Copy any snippet from the menu bar without leaving the app you are working in
- Optionally watch the clipboard and offer to save code you copy elsewhere as a snippet

## Menu bar quick copy

A scissors icon in the menu bar opens a searchable panel for copying a snippet
without leaving the app you are working in. The panel is driven from the
keyboard:

- Type to filter the current scope
- `↑` / `↓` move the selection
- `⏎` copies the selected snippet
- `⌘⏎` reveals the selected snippet in the main window instead
- `⌘1`–`⌘4` switch scope: Favorites, Frequent, Recent, All
- `Esc` clears a typed search, and dismisses the panel once there is nothing to clear

Closing the last window no longer quits the app — it keeps running in the menu
bar so the panel stays reachable while you work elsewhere. The panel footer
carries Quit, because with no window open and another app frontmost the menu
bar is not ours.

## Previews and privacy

### Running previews

Previewing a snippet runs it. Three engines do that: a `WKWebView` for HTML,
CSS, JavaScript, TypeScript, React, and GLSL; an `MTKView` for Metal shaders;
and, for Swift, a compile with the Xcode toolchain — a SwiftUI view is loaded
into the app's own process, and any other Swift runs as a separate program. That is the feature working as intended for code you wrote yourself,
which is where snippets come from today — so execution is something you turn on
rather than something that happens.

- **Run Previews Automatically** is a global setting, off by default. It is
  chosen from a first-launch prompt and changeable in Settings → Preferences.
- With it off, a web or Metal preview waits behind a Run button. Approval is per
  snippet and lasts for that launch only.
- Swift previews always wait for an explicit Run, whatever the setting says, so
  running native code in the app's process is never automatic. They are not in
  the Mac App Store build at all (see [App Store build](#app-store-build)).
- Loading npm modules from esm.sh is a separate grant, per snippet, shown as a
  banner naming the packages. It is the only way a preview reaches the network.

### Swift previews

Open a Swift snippet, switch the panel from **source** to **preview**, and press
**run**. The first build of a snippet takes a few seconds; running unchanged
code again is instant because builds are cached. After an edit the preview
offers **code changed — run again**. It needs Xcode installed; Snippets finds
the Swift compiler through `xcrun`, so it follows `xcode-select`.

What the preview shows depends on what the snippet declares, in this order:

1. **A `#Preview { … }` block** — its body is rendered, exactly as Xcode would.
   This is the way to preview a view that needs init arguments, and
   `@Previewable @State` works for bindings. Only the first `#Preview` counts;
   its name and traits are ignored.
2. **A view** — a `View`, `Shape`, `NSViewRepresentable` or
   `NSViewControllerRepresentable`. `Preview` wins, then `ContentView`, then
   the view no other code in the snippet creates (the composed root rather
   than a subcomponent). It must be creatable with no arguments.
3. **A style or modifier** — a `ButtonStyle` or `PrimitiveButtonStyle` is
   shown on a sample button, a `ToggleStyle` on a live toggle, a
   `ViewModifier` on a line of text.
4. **Anything else** runs as a console program and shows what it prints
   (standard output and standard error together). Top-level code works;
   `@main` works too. A program still running after 10 seconds is stopped.

Things to know:

- `import SwiftUI` and `import AppKit` (or `Foundation` for console code) are
  added if missing.
- A type defined in another snippet is found only if that snippet is one of
  this snippet's **connections** (editor → connections). The two compile as one
  file, connections first.
- Compile errors point at the line in the snippet (`snippet:12:5`), or in a
  connection (`connected snippet 1:3:9`), and common mistakes come with a hint.
- A view runs inside Snippets itself: a crash in the view (a force-unwrap of
  `nil`, say) takes the app down with it. Console programs run separately, so a
  crash there only ends that run.
- Only macOS code works — the build targets macOS 26 with the SDK Xcode
  provides. UIKit and iOS-only APIs fail to compile.

### Clipboard capture

**Offer to Save Copied Code** (Settings → Preferences) is off by default. Turn
it on and the app checks the clipboard once a second — macOS offers no
change notification, so polling is the only mechanism — and when what you copied
looks like code in a language it recognizes, offers to save it as a snippet.

- Content marked concealed, transient, or auto-generated by the app that
  produced it is never captured. Password managers set these markers.
- Copies the app makes itself are ignored.
- A candidate is held in memory only. Nothing is written to the store until you
  choose to save it.

### Import and export

File ▸ Export Library… (⇧⌘E) writes every snippet outside Trash to one
`.snippets` file — collections, connections, saved preview configs and media
included. Export collection… (sidebar), Export… (snippet menu) and export in
select mode write just those. File ▸ Import Snippets… (⇧⌘I), or opening a
`.snippets` file, brings one in; a snippet already in the library asks Skip,
Replace or Stop, with Apply to all. Preview permissions are never exported,
and a replaced snippet loses its own. This is also how to move a library into
the sandboxed App Store build, whose container starts empty.

### Agents (MCP)

The direct-download build serves your library to any AI agent that speaks
the [Model Context Protocol](https://modelcontextprotocol.io) — Claude Code,
Codex, VS Code's Copilot, Cursor, Gemini CLI, Windsurf, Claude Desktop, Zed
and others. Turn on **Settings ▸ Agents ▸ Allow Agent Access**, then pick
your agent from **Copy Setup**:

| Agent | What Copy Setup gives you |
| --- | --- |
| Claude Code | `claude mcp add --scope user snippets -- '/Applications/Snippets.app/Contents/MacOS/Snippets' --mcp-stdio` |
| Codex | `codex mcp add snippets -- '/Applications/Snippets.app/Contents/MacOS/Snippets' --mcp-stdio` |
| VS Code (Copilot) | `code --add-mcp '{"args":["--mcp-stdio"],"command":"…/Snippets","name":"snippets"}'` |
| Anything else | `{"mcpServers": {"snippets": {"command": "…/Snippets", "args": ["--mcp-stdio"]}}}`, to merge into the agent's MCP config (Cursor's `~/.cursor/mcp.json`, Gemini CLI's `~/.gemini/settings.json`, …) |

Whatever the agent, the server is the same stdio command:
`Snippets.app/Contents/MacOS/Snippets --mcp-stdio`.

Agents can `find_snippets`, `list_collections`, `get_snippet` and
`use_snippet` (code ready to paste, with its linked snippets resolved in
order). With **Allow Agents to Edit** on, they can also `create_snippet` and
`update_snippet`, so "save this function as a snippet" works from any of
them. The server tells the agent how: save exactly the code you pointed at,
verbatim, with a short title, its language and a one-line description, then
report the title. Code an agent wraps in a Markdown fence is unwrapped, and
the fence's language tag is used. Agents that support MCP prompts also get a
**save_snippet** prompt (`/mcp__snippets__save_snippet` in Claude Code,
`/save_snippet` in Gemini CLI) that asks for exactly that.

There is no delete; an update replaces the code, and a snippet whose code an
agent changed asks for preview approval again. The agent's process relays to
the running app over a socket only you can open, starting Snippets if it
isn't running; an agent-launched Snippets starts in the background. Only one
copy of Snippets can serve agents at a time: a second copy (a debug build,
say) leaves the running one's socket alone. It isn't in the App Store build.

## Project Structure

- Sources/Snippets/SnippetsApp.swift: app entry point, SwiftData setup, and app environment configuration
- Sources/Snippets/App: shared app environment and appearance settings
- Sources/Snippets/Models: SwiftData models for snippets, collections, and media
- Sources/Snippets/Views: main app screens and modal flows
- Sources/Snippets/Views/Components: reusable UI components and rendering helpers
- Sources/Snippets/Views/Components/Preview: the web, Metal, and Swift preview views
- Sources/Snippets/Views/QuickCopy: the menu bar panel, its result rows, and the capture banner
- Sources/Snippets/Views/Settings: the Settings window — appearance and preferences (app info is in the standard About panel)
- Sources/Snippets/Views/Sidebar: the collection sidebar and its editor sheet
- Sources/Snippets/DesignSystem: design tokens, modifiers, and glass-style components
- Sources/Snippets/Features: view models and pure logic for gallery, editor, preview, and quick copy behavior
- Sources/Snippets/Features/Editor: the snippet editor view model
- Sources/Snippets/Features/Gallery: the gallery view model and collection move tree
- Sources/Snippets/Features/Preview: preview engines, snippet linking, preview parameters, and the preview trust model
- Sources/Snippets/Features/QuickCapture: clipboard capture policy and the code-shape heuristics behind it
- Sources/Snippets/Features/Transfer: the `.snippets` archive format, exporter, importer, and the controller that connects them to panels and alerts
- Sources/Snippets/Features/MCP: the MCP protocol dispatcher, the snippet tools agents call, and the `--mcp-stdio` relay (direct-download build only)
- Sources/Snippets/Features/QuickCopy: quick-copy scopes, results, selection arithmetic, and view model
- Sources/Snippets/Intents: App Intents, entities, and App Shortcuts for Shortcuts/Siri
- Sources/Snippets/Services: theme, language detection, media handling, the menu bar controller, the clipboard monitor, agent access and its socket server, and other shared services
- Sources/Snippets/Core/Services: service protocols shared across the app
- Sources/Snippets/Resources: app icon assets and the vendored web-preview runtimes
- Tests/SnippetsTests: unit tests for view models and app behavior

## Requirements

- macOS 26+ (the app links against the macOS 26 SDK for the Liquid Glass design system)
- Xcode with Swift 6.2 tools; SwiftData macros require the full Xcode toolchain, not the Command Line Tools alone

## Build and Run

`Snippets.xcodeproj` is the only build system — it is what produces the signed
`.app` with its icon, entitlements and App Intents. From the project root:

> SwiftData macros require the full Xcode toolchain, not just the Command Line Tools. If `xcode-select -p` doesn't point at Xcode, run `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```

To run the app, open the project and launch the Snippets scheme.

### App Store build

The `AppStore` build configuration is what Product ▸ Archive uses. On top of
Release it:

- turns on the App Sandbox with `Snippets-AppStore.entitlements` (network
  client for esm.sh, read-only access to files the user picks);
- defines `APP_STORE`, which compiles out the Swift preview engine — no
  `xcrun`, `swiftc` or `dlopen` — so Swift snippets are code-only there.

Debug and Release stay unsandboxed with Swift previews. A sandboxed build keeps
its library in its container (`~/Library/Containers/com.halilbagosi.Snippets`),
not in `~/Library/Application Support`.

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' -configuration AppStore build
```

### Adding files

The project lists source files explicitly (it does not use synchronized
folders), so a new file under `Sources/` has to be added to the `Snippets`
target, and a new file under `Tests/SnippetsTests/` to the `SnippetsTests`
target. Adding it in Xcode does both; adding it on disk alone leaves it
uncompiled.

## Testing

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```

To run the suite against the App Store build (sandboxed host, no Swift engine),
enable testability for that run only — the shipping configuration leaves it off:

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' -configuration AppStore ENABLE_TESTABILITY=YES test
```

The `SnippetsTests` target is hosted by the app, so a test run launches
`Snippets.app` — expect the app to appear briefly.

## Notes

Generated build products, local Xcode state, and temporary editor files are intentionally excluded from source control. The repository ignores these files so local development stays clean.

## License

Snippets is proprietary software, © 2026 Halil Bagosi, all rights reserved.
It is free to use, personally or at work, under the
[End User License Agreement](Sources/Snippets/Resources/EULA.txt), which is
also shown in the app under **Help ▸ License Agreement**. This source is not
licensed for redistribution or modification.

The bundled preview runtimes (React, Babel, Tailwind CSS and Bootstrap with
Popper) are third-party code under their own MIT licences, listed in
[`ThirdPartyNotices.txt`](Sources/Snippets/Resources/ThirdPartyNotices.txt) and
shown in the app under **Help ▸ Third-Party Notices**. Packages a preview loads
from esm.sh are not bundled and stay under their own licences.

## Website

The download page and the support, privacy policy and license pages that the
Help menu links to are in `site/`, served by GitHub Pages from the public
`halilbagosi/halilbagosi.github.io` repo (this repo is private), on the custom
domain in `site/CNAME` (snippets.halilbagosi.com). Keep that file: publishing
mirrors `site/`, so without it the domain would be dropped.

- `site/index.html`, `home.css`, `style.css` and `site.js` are written by
  hand. The page follows the system's light or dark appearance and
  has a toggle to override it; screenshots and clips in `site/media/`
  come in `-light` and `-dark` versions. The app's Help menu links
  (`AppLinks.swift`) and the EULA point at https://snippets.halilbagosi.com.
- The support, privacy and license pages are generated: edit
  `site/pages/<page>.html` (or `EULA.txt` for the license), then run the
  build below. Run it after editing `style.css`, `home.css` or `site.js` too:
  it fingerprints their links (`style.css?v=…`) so browsers don't keep a
  stale copy. Then run

  ```sh
  python3 site/build.py
  ```

To publish, copy everything in `site/` except `build.py` and `pages/` into the
Pages repo and push. The download buttons point at
`releases/latest/download/Snippets.dmg` in that repo, so a release there with a
`Snippets.dmg` asset is what visitors get.
