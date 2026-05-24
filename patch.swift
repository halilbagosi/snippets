struct SidebarSelectionModifier: ViewModifier {
    var isActive: Bool
    var isWindowActive: Bool
    var isText: Bool = false
    var isIcon: Bool = false
    var defaultColor: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isActive ? (isWindowActive ? .white : defaultColor) : defaultColor)
            .animation(nil, value: isActive)
            .animation(nil, value: isWindowActive)
    }
}
