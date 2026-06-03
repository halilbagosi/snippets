import SwiftUI
import AppKit

struct ContentView: View {
    @State private var color = Color.red
    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 38, height: 38)
                .overlay {
                    ColorPicker("", selection: $color)
                        .labelsHidden()
                        .fixedSize()
                        .scaleEffect(5.0)
                        .opacity(0.5) // see where it is
                }
                .clipShape(Circle())
        }
        .frame(width: 200, height: 200)
    }
}
