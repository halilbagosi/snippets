require 'fileutils'
content = File.read("Sources/Snippets/Views/ContentView.swift")

old_toolbar = <<-SWIFT
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
SWIFT

new_toolbar = <<-SWIFT
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if columnVisibility == .all {
                                    columnVisibility = .detailOnly
                                } else {
                                    columnVisibility = .all
                                }
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .liquidGlassSurface(
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous),
                            tint: theme.accent,
                            interactive: true
                        )
                    }
                }
        } detail: {
SWIFT

content = content.sub(old_toolbar.strip, new_toolbar.strip)
File.write("Sources/Snippets/Views/ContentView.swift", content)
