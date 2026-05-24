import re

with open('Sources/Snippets/Views/ContentView.swift', 'r') as f:
    content = f.read()

# Define the unified background helper if not exists
helper = """
@ViewBuilder
func sidebarSelectionBackground(isActive: Bool, isWindowActive: Bool, theme: Theme) -> some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isActive ? (isWindowActive ? Color.accentColor : Color(NSColor.unemphasizedSelectedContentBackgroundColor)) : Color.clear)
        .animation(nil, value: isActive)
        .animation(nil, value: isWindowActive)
}
"""
if "func sidebarSelectionBackground" not in content:
    # insert before "private func sidebarRow"
    content = content.replace("    private func sidebarRow", helper + "\n    private func sidebarRow")

# Replace legacy sidebar background
old_bg = """            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }"""

new_bg = """            .background {
                sidebarSelectionBackground(isActive: isActive, isWindowActive: isWindowActive, theme: theme)
            }"""

content = content.replace(old_bg, new_bg)

# Replace trash background
old_trash_bg = """                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(sidebarSelectionContext == .trash ? Color.red.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
                            }"""
new_trash_bg = """                            .background {
                                sidebarSelectionBackground(isActive: isTrashActive, isWindowActive: isWindowActive, theme: theme)
                            }"""
if old_trash_bg in content:
    content = content.replace(old_trash_bg, new_trash_bg)
else:
    # try another trash background regex if present
    pass

# Replace legacy collection rows background
# It uses isActive = ... and then .fill(isActive ? ...)
# We replaced old_bg globally!

# Now modern sidebar
# modernCollectionTree uses `NavigationLink(value:)` so selection is handled by `List(selection:)`
# Wait, modern sidebar uses List with selection, so we don't need custom background!
# But we DO need custom foregroundStyle for modern sidebar:
old_modern_fg = """.foregroundStyle(isActive ? theme.text : .primary)"""
new_modern_fg = """.foregroundStyle(isActive && isWindowActive ? .white : (isActive ? theme.text : .primary))
                        .animation(nil, value: isActive)
                        .animation(nil, value: isWindowActive)"""
content = content.replace(old_modern_fg, new_modern_fg)

with open('Sources/Snippets/Views/ContentView.swift', 'w') as f:
    f.write(content)

