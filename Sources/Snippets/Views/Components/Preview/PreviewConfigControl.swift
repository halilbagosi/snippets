import SwiftUI

/// Saves and switches preview parameter configurations. Sits beside the
/// code/preview toggle and morphs: a save button until configs exist, a
/// dropdown afterwards.
struct PreviewConfigControl: View {
    let configs: [PreviewParamConfig]
    let activeID: UUID?
    let isDirty: Bool
    let accent: Color
    let theme: Theme
    let onSave: (String) -> Void
    let onUpdate: (UUID) -> Void
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var isNaming = false
    @State private var draftName = ""

    private var activeConfig: PreviewParamConfig? {
        configs.first { $0.id == activeID }
    }

    var body: some View {
        if isNaming {
            nameField
        } else if configs.isEmpty {
            if isDirty {
                FilterTag(
                    label: "save config", icon: "square.and.arrow.down",
                    accent: accent, isSelected: false
                ) {
                    beginNaming()
                }
            }
        } else {
            dropdown
        }
    }

    private var nameField: some View {
        HStack(spacing: 6) {
            TextField("config name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(Mono.font(size: 10))
                .frame(width: 120)
                .onSubmit(commitName)
            Button("save") { commitName() }
                .buttonStyle(.plain)
                .font(Mono.font(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .disabled(trimmedName.isEmpty)
            Button("cancel") { isNaming = false }
                .buttonStyle(.plain)
                .font(Mono.font(size: 10))
                .foregroundStyle(theme.textMuted)
        }
    }

    private var dropdown: some View {
        Menu {
            ForEach(configs) { config in
                Button {
                    onSelect(config.id)
                } label: {
                    Label(config.name, systemImage: config.id == activeID ? "checkmark" : "")
                }
            }
            if isDirty {
                Divider()
                if let active = activeConfig, !active.isDefault {
                    Button("Update \"\(active.name)\"") { onUpdate(active.id) }
                }
                Button("Save as new config…") { beginNaming() }
            }
            let deletable = configs.filter { !$0.isDefault }
            if !deletable.isEmpty {
                Divider()
                Menu("Delete") {
                    ForEach(deletable) { config in
                        Button(config.name, role: .destructive) { onDelete(config.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(Mono.font(size: 10, weight: .semibold))
                Text(activeConfig?.name ?? "config")
                    .font(Mono.font(size: 11, weight: .semibold))
                if isDirty {
                    Circle().fill(accent).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(theme.safeAccentText(accent))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginNaming() {
        draftName = ""
        isNaming = true
    }

    private func commitName() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        onSave(name)
        isNaming = false
    }
}
