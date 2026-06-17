import SwiftUI

struct TestView: View {
    @State var v = false
    var body: some View {
        ZStack {
            Text("A")
            #if os(macOS)
            .padding()
            #endif
            
            Button("B") { v.toggle() }
        }
    }
}
