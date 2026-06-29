    private var sidebar: some View {
        if #available(macOS 26.0, *) {
            modernSidebar
        } else {
            legacySidebar
        }
    }
