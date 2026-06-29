import SwiftUI
struct TestView: View {
    var body: some View {
        Text("Hello")
            .toolbar(removing: .title)
            .toolbar(removing: .sidebarToggle)
    }
}
