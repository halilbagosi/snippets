import SwiftUI

struct TestView: View {
    @State private var selection: String = "all"
    
    var body: some View {
        if #available(macOS 26.0, *) {
            TabView(selection: $selection) {
                Tab("All", systemImage: "square", value: "all") {
                    mainDetailView
                }
                Tab("Trash", systemImage: "trash", value: "trash") {
                    mainDetailView
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            NavigationSplitView {
                List {
                    Text("Sidebar")
                }
            } detail: {
                mainDetailView
            }
        }
    }
    
    @ViewBuilder
    private var mainDetailView: some View {
        if selection == "trash" {
            Text("Trash Detail")
        } else {
            Text("Main Detail")
        }
    }
}
