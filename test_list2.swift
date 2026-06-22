import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selection: String? = "1"
    var body: some View {
        List(selection: $selection) {
            Text("Item 1")
                .tag("1")
            Text("Item 2")
                .tag("2")
        }
        .tint(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        .frame(width: 200, height: 200)
    }
}
