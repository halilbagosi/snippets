import SwiftUI

struct TestView: View {
    var body: some View {
        Text("Hello")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: {}) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
            .controlSize(.large)
    }
}
