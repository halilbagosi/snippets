import re

with open('Sources/Snippets/Views/ContentView.swift', 'r') as f:
    content = f.read()

# We need to make sure the row text/icon are white when active AND window is active.
# Otherwise they are their default colors.
# `WJ4n.swift` has:
#                 Image(systemName: icon)
#                     .font(Mono.font(size: 11, weight: .semibold))
#                     .frame(width: 14)
#                     .foregroundStyle(accent)
#                 Text(title)
#                     .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
#                     .foregroundStyle(isActive ? theme.text : theme.textMuted)

target = """                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(accent)
                Text(title)
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? theme.textMuted : theme.textFaint)"""

replacement = """                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(isActive && isWindowActive ? .white : accent)
                    .animation(nil, value: isActive)
                    .animation(nil, value: isWindowActive)
                Text(title)
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive && isWindowActive ? .white : (isActive ? theme.text : theme.textMuted))
                    .lineLimit(1)
                    .animation(nil, value: isActive)
                    .animation(nil, value: isWindowActive)
                Spacer(minLength: 4)
                Text("\\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isActive && isWindowActive ? .white.opacity(0.72) : (isActive ? theme.textMuted : theme.textFaint))
                    .animation(nil, value: isActive)
                    .animation(nil, value: isWindowActive)"""

content = content.replace(target, replacement)

target_trash = """                                Image(systemName: "trash")
                                    .font(Mono.font(size: 11, weight: .semibold))
                                    .frame(width: 14)
                                    .foregroundStyle(Color.red)
                                Text("trash")
                                    .font(Mono.font(size: 12, weight: .medium))
                                    .foregroundStyle(theme.textMuted)
                                Spacer()
                                Text("\\(allSnippets.filter { $0.deletedAt != nil }.count)")
                                    .font(Mono.font(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.textFaint)"""

# we need to compute isActive for trash
# In legacy sidebar, trash is active when `sidebarSelectionContext == .trash`
replacement_trash = """                                let isTrashActive = sidebarSelectionContext == .trash
                                Image(systemName: "trash")
                                    .font(Mono.font(size: 11, weight: .semibold))
                                    .frame(width: 14)
                                    .foregroundStyle(isTrashActive && isWindowActive ? .white : Color.red)
                                    .animation(nil, value: isTrashActive)
                                    .animation(nil, value: isWindowActive)
                                Text("trash")
                                    .font(Mono.font(size: 12, weight: isTrashActive ? .semibold : .medium))
                                    .foregroundStyle(isTrashActive && isWindowActive ? .white : (isTrashActive ? theme.text : theme.textMuted))
                                    .animation(nil, value: isTrashActive)
                                    .animation(nil, value: isWindowActive)
                                Spacer()
                                Text("\\(allSnippets.filter { $0.deletedAt != nil }.count)")
                                    .font(Mono.font(size: 10, weight: .semibold))
                                    .foregroundStyle(isTrashActive && isWindowActive ? .white.opacity(0.72) : (isTrashActive ? theme.textMuted : theme.textFaint))
                                    .animation(nil, value: isTrashActive)
                                    .animation(nil, value: isWindowActive)"""

content = content.replace(target_trash, replacement_trash)

# Now modern sidebar
# For Modern sidebar, it uses `foregroundStyle(isActive ? theme.text : ...)` etc.
# But it also uses `.background` or `sidebarSelectionBackground`
# Wait, let's just create the helper instantSidebarSelectionStyle
extension = """
extension View {
    func instantSidebarSelectionStyle() -> some View {
        transaction { transaction in
            transaction.animation = nil
        }
    }
}
"""
if "instantSidebarSelectionStyle" not in content:
    content += extension

with open('Sources/Snippets/Views/ContentView.swift', 'w') as f:
    f.write(content)

