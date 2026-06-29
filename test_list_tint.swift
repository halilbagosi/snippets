import SwiftUI
struct TestView: View {
    @State var sel: String?
    var body: some View {
        List(selection: $sel) {
            Text("A").tag("A").tint(.red)
            Text("B").tag("B").tint(.green)
        }
    }
}
