import re

with open('Sources/Snippets/Views/SnippetGalleryView.swift', 'r') as f:
    content = f.read()

# Replace language filter accents
# Previous agent used more saturated colors. In FilterTag for language:
#                     let accent = Color(hex: language.accentHex) ?? theme.accent
#                     FilterTag(
#                         label: "lang:\\(language.rawValue.lowercased())",
#                         icon: language.symbolName,
#                         accent: accent,

# We can make it saturated by default unless it's React
replacement = """                    let baseAccent = Color(hex: language.accentHex) ?? theme.accent
                    let isReact = language.rawValue.lowercased() == "react"
                    let accent = isReact ? baseAccent : baseAccent.saturation(1.5).brightness(0.1)
                    FilterTag(
                        label: "lang:\\(language.rawValue.lowercased())",
                        icon: language.symbolName,
                        accent: accent,"""

target = """                    let accent = Color(hex: language.accentHex) ?? theme.accent
                    FilterTag(
                        label: "lang:\\(language.rawValue.lowercased())",
                        icon: language.symbolName,
                        accent: accent,"""

content = content.replace(target, replacement)

# "disable the card effects when i am in selection mode"
# We need to pass `isSelectionMode` to `SnippetCard`
# Target: `SnippetCard(snippet: snippet)`
# Replace with `SnippetCard(snippet: snippet, isSelectionMode: viewModel.isSelectMode)`
content = content.replace("SnippetCard(snippet: snippet)", "SnippetCard(snippet: snippet, isSelectionMode: viewModel.isSelectMode)")

# And we must ensure SnippetCard takes isSelectionMode and uses it
with open('Sources/Snippets/Views/SnippetGalleryView.swift', 'w') as f:
    f.write(content)

