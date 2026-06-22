import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selection: String? = "1"
    var body: some View {
        List(selection: $selection) {
            Text("Item 1")
                .tag("1")
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection == "1" ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
                )
            Text("Item 2")
                .tag("2")
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection == "2" ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
                )
        }
        .frame(width: 200, height: 200)
    }
}
