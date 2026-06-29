import SwiftUI

@available(macOS 26.0, *)
struct TestView: View {
    var body: some View {
        TabView {
            Tab("Parent", systemImage: "folder") {
                Text("Detail")
            }
            // wait, SwiftUI 16 didn't use `content:` for Tab children, it used Tab(..., role: ...) or something?
        }
    }
}
