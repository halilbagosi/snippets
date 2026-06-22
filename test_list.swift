import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selection: String?
    var body: some View {
        List(selection: $selection) {
            Text("Item 1")
                .tag("1")
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection == "1" ? Color.gray.opacity(0.3) : Color.clear)
                        .padding(.horizontal, 4)
                )
            Text("Item 2")
                .tag("2")
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection == "2" ? Color.gray.opacity(0.3) : Color.clear)
                        .padding(.horizontal, 4)
                )
        }
        .frame(width: 200, height: 200)
    }
}
