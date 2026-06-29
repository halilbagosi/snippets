import SwiftUI

@available(macOS 26.0, *)
struct TestView: View {
    @State private var selection: String? = "all"
    var body: some View {
        TabView(selection: $selection) {
            Tab("All Snippets", systemImage: "square.grid.2x2", value: "all") {
                Text("All Snippets")
            }
            TabSection("Collections") {
                Tab("My Collection", systemImage: "folder", value: "col1") {
                    Text("My Collection Detail")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
