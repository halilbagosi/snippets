import Foundation
import SwiftData

/// The single SwiftData container shared by the SwiftUI app and every App Intent.
/// Intents may run while the app is backgrounded, so both paths must open the
/// same store — two containers on one URL would conflict.
enum SnippetsData {
    @MainActor
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([Snippet.self, MediaItem.self, SnippetCollection.self])
        let appSupport = URL.applicationSupportDirectory
        let storeURL = appSupport.appending(path: "Snippets.store")

        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unresolved error loading SwiftData container: \(error.localizedDescription)")
        }
    }()
}
