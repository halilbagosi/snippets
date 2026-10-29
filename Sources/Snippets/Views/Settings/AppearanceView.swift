import SwiftUI

/// The two tabs of the Settings window, in tab order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Settings"
        case .appearance: "Appearance"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.pointed.fill"
        }
    }

    /// Position in the tab bar, left to right.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The cards of one Settings tab. Settings holds what the app does —
/// deletion, previews, clipboard capture, agents; Appearance holds how it
/// looks — colour scheme, focused mode, hover effects and accent colour.
struct AppearanceView: View {
    let pane: SettingsPane

    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(PreviewTrust.self) private var previewTrust
    @Environment(Onboarding.self) private var onboarding
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    /// Preset accent colour palette. Pink and Yellow are the app icon's pink
    /// and yellow layers (the light end of each gradient in
    /// `SnippetsIcon.icon/icon.json`, display-p3 converted to sRGB); they
    /// replaced the system Pink and Orange, which the icon's dark ends match.
    static let presetColors: [(name: String, hex: String)] = [
        ("Blue",   "#0A84FF"),
        ("Pink",   "#FF6583"),
        ("Yellow", "#FFCA00"),
        ("Green",  "#51C278"),
        ("Indigo", "#5E5CE6"),
        ("Purple", "#BF5AF2"),
        ("Teal",   "#64D2FF"),
        ("Red",    "#FF453A"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            switch pane {
            case .general:
                behaviorCard
                #if !APP_STORE
                agentsCard
                #endif
                #if DEBUG
                debugCard
                #endif
            case .appearance:
                schemeCard
                effectsCard
                accentCard
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSToken.Spacing.md)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            shadowRadius: 12,
            shadowY: 6
        )
    }

    // MARK: - Color Scheme

    private var schemeCard: some View {
        glassCard {
            sectionLabel("Appearance")

            ColorSchemePicker()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Effects

    private var effectsCard: some View {
        @Bindable var settings = appearanceSettings

        return glassCard {
            sectionLabel("Effects")

            behaviorRow(
                icon: "scope",
                title: "Focused Mode",
                caption: "Hide the animated color gradient behind the gallery",
                isOn: $settings.focusedMode
            )

            Divider().opacity(0.5)

            behaviorRow(
                icon: "cursorarrow.motionlines",
                title: "Disable Hover Effects",
                caption: "Turn off hover animations on snippet cards",
                isOn: $settings.disableHoverEffects
            )
        }
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        @Bindable var settings = appearanceSettings
        @Bindable var trust = previewTrust
        @Bindable var capture = ClipboardMonitor.shared

        return glassCard {
            sectionLabel("Behavior")

            behaviorRow(
                icon: "exclamationmark.triangle",
                title: "Confirm Snippet Deletion",
                caption: "Show a confirmation dialogue when deleting a snippet",
                isOn: $settings.confirmSnippetDeletion
            )

            Divider().opacity(0.5)

            behaviorPickerRow(
                icon: "folder.badge.minus",
                title: "Collection Deletion Behavior",
                caption: "What to delete when deleting a collection",
                selection: $settings.collectionDeletionBehavior
            )

            Divider().opacity(0.5)

            behaviorRow(
                icon: "play.rectangle",
                title: "Run Previews Automatically",
                caption: "Off, a preview waits for Run instead of executing when you open a snippet",
                isOn: $trust.autoRunPreviews
            )

            Divider().opacity(0.5)

            // The caption is the user's only notice that the app reads the
            // clipboard, so it says so plainly.
            behaviorRow(
                icon: "doc.on.clipboard",
                title: "Offer to Save Copied Code",
                caption: "Watch the clipboard and offer to save code you copy elsewhere",
                isOn: $capture.isEnabled
            )
        }
    }

    private func behaviorPickerRow(icon: String, title: String, caption: String, selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.safeAccentText(accent))
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    tint: accent.opacity(0.12),
                    shadowRadius: 3,
                    shadowY: 1
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 12)

            Picker("", selection: selection) {
                Text("Ask every time").tag("ask")
                Text("Delete Collection only").tag("collectionOnly")
                Text("Delete Collection & contents").tag("collectionAndContents")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
            .tint(theme.safeAccentText(accent))
        }
    }

    private func behaviorRow(icon: String, title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.safeAccentText(accent))
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    tint: accent.opacity(0.12),
                    shadowRadius: 3,
                    shadowY: 1
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(accent)
        }
    }

    // MARK: - Agents

    #if !APP_STORE
    /// MCP access for AI agents. Edits need their own switch, and there is
    /// no way for an agent to delete, so the caption can promise that.
    private var agentsCard: some View {
        @Bindable var access = AgentAccess.shared

        return glassCard {
            sectionLabel("Agents")

            behaviorRow(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Allow Agent Access",
                // On with nothing serving behind it must say so, not look healthy.
                caption: access.isEnabled && !access.isServing
                    ? access.startProblem ?? "Starting…"
                    : "Let AI agents — Claude Code, Codex, Cursor and any other MCP client — find and use your snippets",
                isOn: $access.isEnabled
            )

            Divider().opacity(0.5)

            behaviorRow(
                icon: "square.and.pencil",
                title: "Allow Agents to Edit",
                caption: "Lets agents save code you point them at as new snippets, and change existing ones. They can never delete; edits replace the existing code.",
                isOn: $access.allowsEdits
            )
            .disabled(!access.isEnabled)

            Divider().opacity(0.5)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.safeAccentText(accent))
                    .frame(width: 30, height: 30)
                    .liquidGlassSurface(
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                        tint: accent.opacity(0.12),
                        shadowRadius: 3,
                        shadowY: 1
                    )

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect an Agent")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text("Pick your agent and copy the setup that adds Snippets to it as an MCP server")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }

                    AgentSetupPicker()
                        .controlSize(.small)
                        .disabled(!access.isEnabled)
                }

                Spacer(minLength: 0)
            }
        }
    }
    #endif

    // MARK: - Debug

    #if DEBUG
    /// Debug builds only: the tour otherwise shows once per install, so
    /// iterating on it would mean clearing defaults between every look.
    private var debugCard: some View {
        glassCard {
            sectionLabel("Debug")

            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.safeAccentText(accent))
                    .frame(width: 30, height: 30)
                    .liquidGlassSurface(
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                        tint: accent.opacity(0.12),
                        shadowRadius: 3,
                        shadowY: 1
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay Onboarding")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Show the welcome tour again over the main window")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }

                Spacer(minLength: 12)

                Button("Replay") {
                    MainWindowOpener.activate()
                    onboarding.present()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }
    #endif

    // MARK: - Accent Color

    private var accentCard: some View {
        glassCard {
            sectionLabel("Accent Color")

            AccentColorPicker()
                .frame(maxWidth: .infinity)
        }
    }
}

#if !APP_STORE
/// Which agent to set up, and a button that copies its setup. Shared by
/// Settings and the welcome tour, which remember the same choice.
struct AgentSetupPicker: View {
    @AppStorage("agentAccess.setupClient") private var client: AgentClient = .claudeCode
    /// Bumped on every copy; drives the button's confirmation.
    @State private var copies = 0
    @State private var showsCopied = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    /// One capsule for both controls. The system draws a glass menu with
    /// less padding than a glass button, so styled by the system the two sat
    /// at different heights side by side.
    private var height: CGFloat { controlSize == .small || controlSize == .mini ? 24 : 30 }
    private var fontSize: CGFloat { controlSize == .small || controlSize == .mini ? 12 : 13 }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Agent", selection: $client) {
                    ForEach(AgentClient.allCases) { option in
                        Label {
                            Text(option.name)
                            if let detail = option.detail { Text(detail) }
                        } icon: {
                            option.logo
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    client.logo
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(client.color)
                        .frame(width: 14, height: 14)
                    Text(client.name)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.down")
                        .font(.system(size: fontSize - 3, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .chrome(height: height, fontSize: fontSize, isEnabled: isEnabled)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Agent")
            .accessibilityValue(Text(client.name))

            Button(action: copy) {
                HStack(spacing: 5) {
                    // The same box as the agent's mark, so both buttons are
                    // one height: the document symbol is taller than text.
                    Image(systemName: showsCopied ? "checkmark" : "doc.on.doc")
                        .resizable()
                        .scaledToFit()
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : copies)
                        .frame(width: 14, height: 14)
                    // Both words always laid out, so the button is as wide as
                    // "Copied" from the start, and swapped by opacity rather
                    // than morphed: the text morph drew each word in a layer
                    // of its own, which outlined the text with a faint box.
                    ZStack(alignment: .leading) {
                        Text("Copy").opacity(showsCopied ? 0 : 1)
                        Text("Copied").opacity(showsCopied ? 1 : 0)
                    }
                }
                .foregroundStyle(showsCopied ? Color.green : Color.primary)
                .chrome(height: height, fontSize: fontSize, isEnabled: isEnabled)
            }
            .buttonStyle(.plain)
            .help("Copy the setup for \(client.name)")
        }
        .animation(DSToken.Motion.toggle, value: client)
    }

    private func copy() {
        Clipboard.copy(client.setup(executablePath: Bundle.main.executablePath ?? ""))
        copies += 1
        let copy = copies
        withAnimation(DSToken.Motion.toggle) { showsCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            // A later copy restarts the confirmation.
            guard copy == copies else { return }
            withAnimation(DSToken.Motion.toggle) { showsCopied = false }
        }
    }
}

private extension View {
    /// The agent picker's capsule: a fixed height, so its two halves match.
    func chrome(height: CGFloat, fontSize: CGFloat, isEnabled: Bool) -> some View {
        font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, height * 0.42)
            .frame(height: height)
            .contentShape(Capsule())
            // Glass behind the label, not around it: a label inside
            // `glassEffect` is composited into the glass, and while the Copy
            // button's text and symbol swap, the swapping content showed as
            // a dark box inside the capsule.
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension AgentClient {
    /// The agent's mark: Simple Icons' (CC0) Claude, OpenAI and GitHub
    /// Copilot logos, bundled as template vectors, and a symbol for the rest.
    var logo: Image {
        switch self {
        case .claudeCode: Image("AgentLogoClaude")
        case .codex: Image("AgentLogoOpenAI")
        case .vsCode: Image("AgentLogoCopilot")
        case .other: Image(systemName: "ellipsis.curlybraces")
        }
    }

    /// The agent's signature colour, for its mark.
    var color: Color {
        switch self {
        case .claudeCode: Color(red: 0.851, green: 0.467, blue: 0.341)   // Claude's #D97757
        case .codex: .primary                                              // OpenAI's black / white
        case .vsCode: Color(red: 0.0, green: 0.478, blue: 0.8)             // VS Code's #007ACC
        case .other: .secondary
        }
    }
}
#endif
