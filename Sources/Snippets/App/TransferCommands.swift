import SwiftUI

/// File ▸ Import Snippets… / Export Library…
struct TransferCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import Snippets…") { SnippetTransferController.shared.importWithPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Library…") { SnippetTransferController.shared.exportLibrary() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}
