import SwiftUI

@available(macOS 26.0, *)
struct TestView: View {
    var body: some View {
        TabView {
            Tab("Library", systemImage: "book") {
                Text("Library")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
