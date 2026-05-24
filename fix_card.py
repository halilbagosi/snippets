import re

with open('Sources/Snippets/Views/SnippetGalleryView.swift', 'r') as f:
    content = f.read()

# Add isSelectionMode to SnippetCard
if "var isSelectionMode: Bool = false" not in content:
    content = content.replace("struct SnippetCard: View {", "struct SnippetCard: View {\n    var isSelectionMode: Bool = false")

# Disable hover effect scaling
content = content.replace(".scaleEffect(isHovering ? 1.02 : 1.0)", ".scaleEffect(isHovering && !isSelectionMode ? 1.02 : 1.0)")
content = content.replace(".rotation3DEffect(.degrees(isHovering ? 2 : 0)", ".rotation3DEffect(.degrees(isHovering && !isSelectionMode ? 2 : 0)")
content = content.replace("offset(y: isHovering ? -4 : 0)", "offset(y: isHovering && !isSelectionMode ? -4 : 0)")

with open('Sources/Snippets/Views/SnippetGalleryView.swift', 'w') as f:
    f.write(content)
