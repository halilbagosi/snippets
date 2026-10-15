# Snippets — App Store Launch Readiness Checklist

**Status:** Pre-launch audit checklist  
**Platform:** macOS 26+ target, SwiftUI + SwiftData  
**Distribution:** Mac App Store  
**Last audited:** 2026-09-13  
**Purpose:** Agent-ready implementation, legal, privacy, security, App Store Connect, and HIG checklist.

This document is based on a read-only review of the current repository. It is not legal advice. Legal/privacy wording, jurisdictional obligations, third-party contracts, and the final App Store privacy answers must be reviewed by qualified counsel before submission.

Do not mark an item complete without attaching evidence: a commit, test result, archive inspection, screenshot, policy URL, or written legal decision.

## Launch decision

The current build must not be submitted yet. The following are launch gates:

- [ ] App Sandbox is enabled and verified in the signed Release archive.
- [ ] A decision has been made about native Swift preview execution. The current `swiftc` + `dlopen` architecture is a likely Mac App Store review blocker.
- [ ] A public privacy policy is live, linked from inside the app, and entered in App Store Connect.
- [ ] Terms/EULA, third-party notices, support contact, copyright, and asset-license records are complete.
- [ ] CDN/network behavior is explicitly consented to, documented, revocable, and tested.
- [ ] Release signing, deployment target, versioning, archive validation, and clean-machine behavior are verified.
- [ ] VoiceOver, keyboard navigation, contrast, text scaling, reduced motion/transparency, and localization have been tested.
- [ ] App Store Connect metadata, App Privacy, export compliance, age rating, content rights, and review notes are complete.

## Priority definitions

- **P0 — submission blocker:** Do not submit until resolved or an explicit Apple/legal decision is recorded.
- **P1 — required before release:** Required for privacy, security, legal, reliability, or review readiness.
- **P2 — quality gate:** Required for a polished, supportable, accessible release; may be scheduled separately only with an explicit decision.

## Apple source set

Use the current versions of these documents when making final decisions:

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [App Store Connect — App Information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [App Store Connect — Platform Version Information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [App Store Connect — App Privacy](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)
- [Manage App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Apple User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing Data Use in Privacy Manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [Export Compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [HIG — Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [HIG — Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [HIG — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [HIG — Focus and Selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- [HIG — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [HIG — Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

## Current codebase findings

These are starting facts for the implementing agent. Re-check them after changes.

### Current high-risk findings

| ID | Finding | Evidence | Priority |
|---|---|---|---|
| F-01 | App Sandbox is disabled for Debug and Release; no entitlements file is configured. | [`project.pbxproj`](/Users/halilbagosi/snippets/Snippets.xcodeproj/project.pbxproj:1139), [`project.pbxproj`](/Users/halilbagosi/snippets/Snippets.xcodeproj/project.pbxproj:1163) | P0 |
| F-02 | Swift preview locates `xcrun`/`swiftc`, compiles user source, writes a dylib, and loads it into the app process. | [`SwiftPreviewBuilder.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift:27), [`SwiftPreviewBuilder.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Features/Preview/SwiftPreviewBuilder.swift:205) | P0 |
| F-03 | There is no in-app privacy-policy, terms, support, or license-notices link in About. | [`AboutView.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Views/Settings/AboutView.swift:1) | P0 |
| F-04 | React/npm preview imports can reach `https://esm.sh` after a persistent per-snippet grant. | [`PreviewTrust.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Features/Preview/PreviewTrust.swift:20), [`WebPreviewHTMLBuilder.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Features/Preview/WebPreviewHTMLBuilder.swift:1175) | P0 |
| F-05 | Release target/configuration is inconsistent with the stated macOS 26+ product target; copyright is blank. | [`project.pbxproj`](/Users/halilbagosi/snippets/Snippets.xcodeproj/project.pbxproj:1150) | P0 |
| F-06 | Vendored JavaScript/CSS has incomplete provenance and no bundled license-notice system; Babel’s exact version is unknown. | [`VENDOR.md`](/Users/halilbagosi/snippets/Sources/Snippets/Resources/WebPreview/VENDOR.md:1) | P1 |
| F-07 | Quick Capture polls the general pasteboard once per second when enabled and reads string contents. | [`ClipboardMonitor.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Services/ClipboardMonitor.swift:9) | P1 |
| F-08 | App Intents can return, copy, or create arbitrary snippet code. | [`CopySnippetIntent.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Intents/Actions/CopySnippetIntent.swift:1), [`FindSnippetsIntent.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift:1) | P1 |
| F-09 | The Help menu is replaced with an empty command group. | [`SnippetsApp.swift`](/Users/halilbagosi/snippets/Sources/Snippets/SnippetsApp.swift:158) | P1 |
| F-10 | Settings uses a fixed, non-resizable custom window rather than standard macOS Settings chrome. | [`SettingsView.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Views/Settings/SettingsView.swift:31), [`SettingsView.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Views/Settings/SettingsView.swift:175) | P1 |

### Positive findings to preserve

- Quick Capture is opt-in and off by default.
- Clipboard candidates are held in memory until accepted; the monitor does not intentionally write them to disk.
- Preview auto-run defaults to off.
- Web preview uses a nonpersistent `WKWebsiteDataStore`.
- Web navigation is restricted to `about:` and content rules attempt to block ordinary network access.
- No obvious analytics SDK, advertising SDK, account system, cloud database, or telemetry backend was found.
- Vendored preview runtimes are committed and checksum-checked in CI rather than fetched during the build.
- The app already observes reduced-motion settings in several views.

Do not describe these protections as absolute security guarantees until they are tested in the final Release archive.

## P0 — architecture and App Review blockers

### P0-001 — Enable App Sandbox

- [ ] Add an app entitlements file and configure it for Debug and Release as appropriate.
- [ ] Set `ENABLE_APP_SANDBOX = YES` for the Mac App Store Release configuration.
- [ ] Add only required capabilities:
  - [ ] network client for approved CDN requests, if retained;
  - [ ] user-selected file read/write for imported media;
  - [ ] any capability required by App Intents or automation, if applicable.
- [ ] Remove unnecessary entitlements.
- [ ] Confirm the app does not depend on arbitrary paths outside its container.
- [ ] Migrate existing unsandboxed Application Support data into the sandbox container, if migration is supported.
- [ ] Test a clean install and an upgrade from the current unsandboxed build.
- [ ] Test SwiftData store creation, media import, media deletion, Trash, restore, export, and Quick Copy in the sandbox.
- [ ] Inspect the signed archive’s entitlements with `codesign` and retain the output as evidence.

Acceptance criteria: the Release archive is sandboxed, starts without Xcode or development permissions, and all supported user workflows work inside the container.

### P0-002 — Decide the fate of native Swift previews

The current design compiles and dynamically loads user-authored Swift code. This is both a security boundary problem and a likely App Review problem under Apple’s self-contained/code-execution rules.

- [ ] Product decision: remove native Swift execution from the Mac App Store build, redesign it, or request Apple pre-review guidance.
- [ ] If removed:
  - [ ] Hide or disable the Swift preview language in the Mac App Store build.
  - [ ] Remove `xcrun`/`swiftc` runtime dependency from that build.
  - [ ] Replace the feature with a clear “not available in the App Store version” state.
  - [ ] Update documentation, screenshots, marketing copy, and reviewer notes.
- [ ] If retained:
  - [ ] Obtain written Apple guidance before submission.
  - [ ] Define the exact code-execution model and threat boundary.
  - [ ] Ensure the app is self-contained and does not rely on optional Xcode installation.
  - [ ] Prove that user code cannot access app data, credentials, network, subprocesses, or TCC-protected resources outside the intended scope.
  - [ ] Add resource limits, timeouts, crash containment, and denial-of-service protection.
  - [ ] Treat HMAC cache integrity as tamper detection only, not sandboxing.

Acceptance criteria: the team has a documented distribution decision and the App Store build no longer has an unresolved arbitrary-native-code execution path.

### P0-003 — Make the app self-contained

- [ ] Confirm every runtime resource is inside the signed app bundle or an approved sandbox location.
- [ ] Remove assumptions that `/usr/bin/xcrun`, Xcode, developer SDKs, or external toolchains exist on the customer’s Mac.
- [ ] Verify no runtime download installs code or resources that change app functionality.
- [ ] Verify no generated executable/dylib is loaded from a user-writable location in the App Store build.
- [ ] Verify the app does not install launch agents, login items, daemons, or background processes without explicit user action and a clear product need.
- [ ] Verify quitting the app actually quits it unless the user explicitly enabled a menu-bar/background behavior.

### P0-004 — Release configuration and archive integrity

- [ ] Align the deployment target with the actual product requirement and README/agent instructions.
- [ ] Set a nonempty marketing version and monotonically increasing build number.
- [ ] Set the copyright field.
- [ ] Configure the correct Mac App Store distribution signing.
- [ ] Confirm Release does not contain debug dylibs, test hooks, local paths, development URLs, or diagnostics that reveal user content.
- [ ] Build an archive on the supported Xcode toolchain.
- [ ] Test the exported app on a clean Mac account with no Xcode installed.
- [ ] Test offline launch and first-run behavior.

## P0/P1 — privacy, legal, and transparency

### P0-005 — Publish and link the privacy policy

- [ ] Publish a stable HTTPS privacy-policy URL.
- [ ] Add the same link to the About/Help UI.
- [ ] Add the URL to App Store Connect App Privacy information.
- [ ] Add a support/contact address.
- [ ] Version the policy and record its effective date.
- [ ] Define how users can request access, correction, deletion, or clarification.
- [ ] Define how policy changes are communicated.

The policy must accurately describe:

- [ ] Snippet code, titles, descriptions, collections, favorites, counters, timestamps, and UUIDs.
- [ ] Imported media and where it is stored.
- [ ] Clipboard access when Quick Capture is enabled.
- [ ] Preview code execution and its risks.
- [ ] Network requests to `esm.sh` and any other external service.
- [ ] App Intents and Shortcuts returning or copying snippet content after user invocation.
- [ ] Local preferences, preview grants, and appearance settings.
- [ ] Trash retention and permanent deletion behavior.
- [ ] Cache files, generated source, backups, Time Machine copies, and what the app cannot delete outside its control.
- [ ] Third-party processors/service providers.
- [ ] Security contact and incident notification process.

### P0-006 — Define consent and capability UX

#### Quick Capture

- [ ] Keep the feature disabled by default.
- [ ] Explain exactly what enabling it does: periodic pasteboard polling and reading text contents.
- [ ] Explain what happens to a detected candidate before acceptance.
- [ ] Show an always-visible enabled state in Settings/menu bar/panel.
- [ ] Provide a one-step disable action.
- [ ] Do not show full clipboard contents in logs, crash reports, notifications, or analytics.
- [ ] Test password managers, secret values, transient pasteboard types, and large payloads.
- [ ] Do not claim that pasteboard markers reliably identify all secrets.

#### Preview execution

- [ ] Keep automatic preview execution off by default unless there is a documented reason to change it.
- [ ] State that opening/running a preview executes user-authored code.
- [ ] Use clear “Run preview” wording rather than ambiguous toggles.
- [ ] Explain resource, crash, and data-access risks in the first-run policy prompt.

#### CDN modules

- [ ] Use explicit wording such as “Allow this preview to load third-party packages from esm.sh.”
- [ ] State that this makes network requests to a third party.
- [ ] Show the package names/specifiers before approval.
- [ ] Provide global and per-snippet revocation.
- [ ] Consider session-scoped or expiring grants rather than permanent grants.
- [ ] Do not describe network access as impossible if any document path can bypass the intended policy.

### P1-007 — App Privacy questionnaire

- [ ] Inventory all app and third-party data flows.
- [ ] Determine which data is transmitted off-device versus merely stored locally.
- [ ] Determine whether `esm.sh` or another service collects request metadata.
- [ ] Determine whether any data is linked to identity/device or used for tracking.
- [ ] Answer App Store Connect’s data-type, purpose, linked, and tracking fields accurately.
- [ ] Revisit the answers for every future SDK, analytics, crash-reporting, sync, or CDN change.

Do not claim “no data collected” without verifying third-party network behavior and Apple’s current definitions.

### P1-008 — Terms of Use / custom EULA

Apple’s standard EULA may apply automatically, but custom terms are recommended because Snippets executes code and loads third-party packages.

- [ ] Decide whether to publish custom Terms of Use/EULA.
- [ ] Link it from About and Help.
- [ ] Cover the user’s ownership of snippets and media.
- [ ] State that users are responsible for their code, imported files, dependencies, licenses, and network content.
- [ ] Warn that previews execute code and may consume CPU, memory, GPU, or network resources.
- [ ] Prohibit malware, abuse, illegal content, unauthorized data, and infringement.
- [ ] Explain third-party package/CDN terms.
- [ ] State storage, backup, availability, and deletion limitations.
- [ ] Include warranty disclaimer, liability limitations, governing law, and contact information.
- [ ] Have counsel review the terms for every intended distribution jurisdiction.

### P1-009 — Jurisdictional privacy and consumer-law review

Have counsel determine applicability of:

- [ ] GDPR/UK GDPR and local European privacy laws.
- [ ] CCPA/CPRA or other US state privacy laws.
- [ ] Consumer protection, accessibility, and electronic communications laws.
- [ ] Data-transfer requirements for any CDN or service provider.
- [ ] Data processor/controller roles and any required data-processing agreements.
- [ ] EU Digital Services Act trader/contact obligations, if the distribution model makes them applicable.
- [ ] Cookie/tracking obligations for the policy/support website.

The current app appears local-first and accountless, which reduces scope but does not eliminate these checks if data is transmitted to third parties.

### P1-010 — Third-party licenses, trademarks, and content rights

- [ ] Identify every bundled JavaScript, CSS, font, icon, image, video, and sample.
- [ ] Verify exact package versions and source URLs.
- [ ] Resolve the unknown Babel version in [`VENDOR.md`](/Users/halilbagosi/snippets/Sources/Snippets/Resources/WebPreview/VENDOR.md:1).
- [ ] Replace floating CDN references such as `@4` with exact versions in provenance records.
- [ ] Verify checksums against the exact source artifact.
- [ ] Include required MIT/BSD/Apache and other notices in the app bundle or a Notices screen.
- [ ] Confirm rights to the app icon and downloaded-looking image assets such as `pngegg.png`.
- [ ] Confirm rights to screenshots, previews, package names, and trademarks used in marketing.
- [ ] Create a maintained `NOTICE`/third-party inventory with owner, license, source, version, checksum, and attribution text.

## P1 — security implementation checklist

### Web preview isolation

- [ ] Keep web content in `WKWebView`; do not add a second browser/network path.
- [ ] Test every generated-document path with CSP enabled, including full-document passthrough.
- [ ] Verify `connect-src 'none'` actually blocks fetch, XHR, WebSocket, beacon, EventSource, and form submission when CDN access is denied.
- [ ] Verify `img-src`, `media-src`, `frame-src`, `object-src`, `base-uri`, and `form-action` behavior.
- [ ] Treat `'unsafe-inline'` and `'unsafe-eval'` as deliberate risk decisions, not complete isolation.
- [ ] Prevent arbitrary URL imports and redirects where possible.
- [ ] Restrict package specifiers to an allowlist and pin versions.
- [ ] Test package names containing encoded data, query strings, redirects, and malicious characters.
- [ ] Ensure CDN grants are cleared when snippets are deleted or permanently removed.
- [ ] Do not persist website data unless there is a documented need.

### Native preview/code execution

- [ ] Do not ship unsandboxed in-process user-code execution in the App Store build.
- [ ] If a supported code runner remains, define a process boundary, filesystem boundary, network boundary, resource limits, timeout, cancellation, and crash recovery.
- [ ] Prevent access to Keychain, clipboard, user files, environment variables, subprocesses, and app databases unless explicitly required.
- [ ] Test malicious snippets, infinite loops, memory exhaustion, thread creation, file access, process spawning, and network attempts.
- [ ] Never treat cache authentication as execution containment.

### Clipboard and sensitive data

- [ ] Avoid logging pasteboard values.
- [ ] Avoid including snippet contents in error messages or telemetry.
- [ ] Use secure redaction in diagnostics.
- [ ] Test interaction with password managers and sensitive pasteboard types.
- [ ] Document that users should disable Quick Capture when handling secrets if appropriate.

### Data at rest and deletion

- [ ] Document whether local data is encrypted by the app or merely protected by macOS/file permissions.
- [ ] Do not claim encryption at rest unless implemented and verified.
- [ ] Set restrictive permissions on generated files/directories.
- [ ] Ensure media filenames and paths cannot escape the intended directory.
- [ ] Validate imported filenames, extensions, symlinks, and path traversal.
- [ ] Remove orphaned media and preview artifacts during deletion/cleanup.
- [ ] Handle SwiftData save failures visibly.
- [ ] Test interrupted saves, disk-full conditions, permission errors, and corrupted stores.

### App Intents

- [ ] Confirm content is returned only after explicit user invocation.
- [ ] Minimize code returned in search/result previews.
- [ ] Test Shortcuts history, Siri suggestions, Spotlight, and automation logs for accidental content exposure.
- [ ] Document App Intent behavior in the privacy policy.

### Supply chain and CI

- [ ] Keep vendored runtime checksum verification in CI.
- [ ] Pin all runtime dependencies and record licenses.
- [ ] Run dependency auditing for build-time dependencies.
- [ ] Review CI permissions and secrets.
- [ ] Ensure CI does not upload source, snippets, clipboard content, or private artifacts.
- [ ] Protect release signing credentials and App Store Connect API keys.
- [ ] Require review for changes to preview runtimes, CSP, entitlements, and data-flow code.

### Security response

- [ ] Publish a security contact.
- [ ] Define how users report vulnerabilities.
- [ ] Define triage, severity, disclosure, and emergency-update procedures.
- [ ] Prepare a process for revoking a compromised CDN/runtime dependency.
- [ ] Keep a list of shipped versions and supported versions.

## P1/P2 — HIG and accessibility implementation

### Help, support, and standard macOS behavior

- [ ] Restore a meaningful Help menu; do not leave `CommandGroup(replacing: .help) { }` empty.
- [ ] Add Help links for documentation, privacy, terms, support, and third-party notices.
- [ ] Preserve standard Settings access and keyboard shortcut behavior.
- [ ] Verify title-bar, traffic-light, full-screen, close, minimize, and window-discovery behavior.
- [ ] Ensure menu-bar functionality is discoverable and has a VoiceOver description.

### Settings window

- [ ] Test the fixed 520×720 settings window on small displays.
- [ ] Test with large accessibility text and localized strings.
- [ ] Test keyboard navigation between custom tabs and every control.
- [ ] Ensure selected tab, focus, and activation are exposed to VoiceOver.
- [ ] Reconsider standard macOS Settings toolbar panes if the custom chrome creates discoverability or accessibility problems.
- [ ] Ensure the non-resizable window never clips content or hides controls.

### Accessibility semantics

- [ ] Replace gesture-based button semantics with native `Button` controls where possible.
- [ ] Verify [`QuickCopyRow.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Views/QuickCopy/QuickCopyRow.swift:10) has a usable VoiceOver action and full-keyboard action.
- [ ] Verify [`GallerySection.swift`](/Users/halilbagosi/snippets/Sources/Snippets/Views/Components/GallerySection.swift:185) does not combine children in a way that hides nested actions.
- [ ] Add labels, roles, hints, and error descriptions for Web, Metal, and video previews.
- [ ] Provide a text fallback for preview output that cannot be meaningfully inspected by VoiceOver.
- [ ] Test all alerts, banners, toasts, menus, sheets, and popovers with VoiceOver.
- [ ] Test Full Keyboard Access without a mouse.
- [ ] Test focus order after opening previews, changing tabs, deleting/restoring items, and showing Quick Copy.

### Color, contrast, and motion

- [ ] Validate normal text at 4.5:1 contrast and large/bold text at 3:1.
- [ ] Test Light Mode, Dark Mode, Increase Contrast, and reduced transparency.
- [ ] Do not communicate permission, enabled/disabled state, selection, or errors with color alone.
- [ ] Ensure focus rings remain visible over glass backgrounds.
- [ ] Test Reduce Motion for every custom animation and transition.
- [ ] Test Reduce Transparency and high-contrast settings for the glass system.
- [ ] Test the dark-only Metal preview against accessibility requirements.

### Typography and localization

- [ ] Replace fixed font sizes with system text styles where appropriate.
- [ ] Test 100%, 150%, and 200% accessibility text sizes.
- [ ] Test long package names, long snippet titles, errors, and translated strings.
- [ ] Ensure buttons and alerts do not truncate important meaning.
- [ ] Add localization infrastructure or document the supported language scope.
- [ ] Verify dates, numbers, keyboard shortcuts, and pluralization.

### Permission and alert wording

- [ ] Use standard button roles and clear affirmative/destructive/cancel actions.
- [ ] Use explicit labels such as “Run Preview” and “Allow Package Loading from esm.sh”.
- [ ] Explain consequences before enabling clipboard polling or network access.
- [ ] Keep alerts concise and recoverable.
- [ ] Ensure destructive actions have undo or confirmation where appropriate.

## P1 — reliability and data lifecycle

- [ ] Replace fatal store initialization with a recoverable error UI and export/recovery path.
- [ ] Do not swallow important SwiftData save errors.
- [ ] Test first launch, upgrade, downgrade if supported, missing/corrupt store, disk full, read-only directory, and permission errors.
- [ ] Test Trash restore, permanent delete, automatic cleanup, and failed cleanup.
- [ ] Confirm deleted preview grants cannot be inherited by a new/reused snippet UUID.
- [ ] Confirm media deletion and orphan cleanup.
- [ ] Confirm cache cleanup does not delete files belonging to another installation or user.
- [ ] Verify copy counts, favorites, timestamps, and UUID backfill are durable.
- [ ] Add user-facing recovery instructions for failed imports and previews.

## P1 — App Store Connect metadata and legal submission fields

- [ ] Bundle ID matches the signed product and App Store Connect record.
- [ ] App name, subtitle, category, description, keywords, and promotional text are accurate.
- [ ] Screenshots show the actual shipped UI and do not imply unavailable native Swift execution.
- [ ] App preview videos, if used, show real functionality.
- [ ] Support URL leads to actual support/contact information.
- [ ] Privacy-policy URL is public and stable.
- [ ] User Privacy Choices URL is supplied if useful/applicable.
- [ ] Copyright is nonempty and accurate.
- [ ] Age rating is completed accurately.
- [ ] Content rights are confirmed for every icon, image, screenshot, preview, and bundled dependency.
- [ ] Export compliance is complete.
- [ ] App Privacy details are complete and match the privacy policy.
- [ ] EU trader/contact information is completed if applicable.
- [ ] Pricing, availability, tax, banking, and required agreements are complete.
- [ ] Reviewer notes explain Quick Capture, preview execution, CDN consent, and any unavailable features.
- [ ] Test credentials are not needed; if they are, provide them securely and only if the product later adds accounts.

## Verification plan

### Build and test

Run with the project’s required Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Snippets.xcodeproj \
  -scheme Snippets \
  -destination 'platform=macOS' \
  -configuration Release \
  build
```

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Snippets.xcodeproj \
  -scheme Snippets \
  -destination 'platform=macOS' \
  test
```

- [ ] All tests pass on the supported Xcode/macOS combination.
- [ ] Tests run against Release-like settings, not only Debug.
- [ ] Add regression tests for sandboxed paths and data migration.
- [ ] Add network-denial and CDN-grant tests.
- [ ] Add malicious-input and deletion-integrity tests.
- [ ] Add accessibility smoke tests for the highest-risk controls.

### Archive inspection

For the final archive/app:

```sh
codesign --display --entitlements :- "/path/to/Snippets.app"
codesign --verify --deep --strict --verbose=2 "/path/to/Snippets.app"
spctl --assess --type execute --verbose "/path/to/Snippets.app"
plutil -p "/path/to/Snippets.app/Contents/Info.plist"
```

- [ ] Entitlements are minimal and expected.
- [ ] Bundle identifier, version, build, copyright, category, and deployment target are correct.
- [ ] No development paths or private files are embedded.
- [ ] No unapproved executable code is downloaded or loaded.
- [ ] All required notices/policies/resources are present.

### Manual security matrix

- [ ] Offline launch.
- [ ] IPv6-only network.
- [ ] Network denied by sandbox.
- [ ] CDN denied and CDN allowed.
- [ ] Malicious package specifier.
- [ ] HTML with fetch/XHR/WebSocket/beacon/form/iframe attempts.
- [ ] Infinite loop and memory-heavy preview.
- [ ] Malformed snippet and corrupt media.
- [ ] Symlink/path traversal import.
- [ ] Clipboard containing passwords, tokens, private keys, and large text.
- [ ] App Intents invoked from Shortcuts and Siri.
- [ ] App quit/relaunch/background behavior.
- [ ] Crash during save/delete/preview compilation.
- [ ] Upgrade from an unsandboxed pre-release build.

### Manual HIG/accessibility matrix

- [ ] VoiceOver enabled.
- [ ] Full Keyboard Access enabled.
- [ ] Light Mode.
- [ ] Dark Mode.
- [ ] Increase Contrast.
- [ ] Reduce Motion.
- [ ] Reduce Transparency.
- [ ] 150–200% text size.
- [ ] Small display and minimum window size.
- [ ] Long/localized strings.
- [ ] Screen recording/review of all permission and error states.

## Final sign-off record

Record the following before submission:

| Area | Owner | Evidence/link | Date | Status |
|---|---|---|---|---|
| App Sandbox and entitlements |  |  |  | ☐ |
| Native Swift preview decision |  |  |  | ☐ |
| Privacy policy |  |  |  | ☐ |
| Terms/EULA |  |  |  | ☐ |
| Data inventory/App Privacy |  |  |  | ☐ |
| Third-party licenses/assets |  |  |  | ☐ |
| Export compliance |  |  |  | ☐ |
| Release archive/signing |  |  |  | ☐ |
| Security testing |  |  |  | ☐ |
| Accessibility/HIG testing |  |  |  | ☐ |
| App Store Connect metadata |  |  |  | ☐ |
| Legal review |  |  |  | ☐ |

## Definition of done

The app is ready for submission only when:

1. Every P0 item is complete or has an explicit written Apple/legal decision.
2. Every P1 item has evidence or an approved exception.
3. The final archive is sandboxed, signed, self-contained, and tested on a clean Mac.
4. The privacy policy, terms, App Privacy answers, and actual runtime behavior agree.
5. The app does not expose an unresolved arbitrary-native-code execution path in the Mac App Store build.
6. Accessibility and HIG checks pass in all supported appearance and accessibility modes.
7. App Store Connect reviewer notes accurately describe how to exercise all gated features.

