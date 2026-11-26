#if !APP_STORE
import SwiftUI

/// The agent, CLI location and model rows of the Efficiency Rating card. The
/// card chrome and the on/off switch come from `AppearanceView`, so they match
/// the other cards; this view is what sits under that switch.
struct EfficiencyRatingSettings: View {
    @Environment(\.colorScheme) private var colorScheme

    let settings: EfficiencySettings
    @State private var catalog = AgentModelCatalog(models: [AgentModelCatalog.defaultOption], efforts: [])

    private var theme: Theme { Theme.current(colorScheme) }

    /// Agents with a rater. Others are not offered (Codex did not qualify).
    static var ratableAgents: [AgentClient] {
        AgentClient.allCases.filter { EfficiencySettings.executableName(for: $0) != nil }
    }

    /// The muted line under the picker: where the CLI was found, or that it
    /// was not (the panel stays hidden until it is).
    static func statusLine(agent: AgentClient, path: URL?) -> String {
        guard let path else { return "\(agent.name) was not found. Install it and it appears here." }
        return (path.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Agent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    Spacer(minLength: 12)
                    Picker("Agent", selection: $settings.agent) {
                        ForEach(Self.ratableAgents) { option in
                            Label {
                                Text(option.name)
                            } icon: {
                                option.logo
                            }
                            .tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text(Self.statusLine(agent: settings.agent, path: settings.cliPath))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider().opacity(0.5)

            dropdownRow(
                title: "Model",
                detail: "Default uses the agent's own choice",
                options: AgentModelCatalog.including(settings.model(for: settings.agent), in: catalog.models),
                selection: Binding(
                    get: { settings.model(for: settings.agent) },
                    set: { settings.setModel($0, for: settings.agent) }
                )
            )

            if !catalog.efforts.isEmpty {
                Divider().opacity(0.5)

                dropdownRow(
                    title: "Effort",
                    detail: "How hard the model thinks before answering",
                    options: AgentModelCatalog.including(settings.effort(for: settings.agent), in: catalog.efforts),
                    selection: Binding(
                        get: { settings.effort(for: settings.agent) },
                        set: { settings.setEffort($0, for: settings.agent) }
                    )
                )
            }
        }
        // Settings forces a fresh lookup (the locator caches "not found").
        .task(id: settings.agent) {
            catalog = AgentModelCatalog.builtIn(for: settings.agent)
            await settings.forceRefreshCLIPath()
            await refreshCatalogFromCLI()
        }
    }

    /// Claude Code lists its effort levels and model aliases in `--help`;
    /// read them from the installed CLI so the menus match its version.
    private func refreshCatalogFromCLI() async {
        let agent = settings.agent
        guard agent == .claudeCode, let cli = settings.cliPath,
              let help = await AgentHelpReader.help(executable: cli),
              settings.agent == agent else { return }
        catalog = AgentModelCatalog.claude(fromHelp: help)
    }

    private func dropdownRow(
        title: String, detail: String,
        options: [AgentModelCatalog.Option], selection: Binding<String>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 12)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
#endif
