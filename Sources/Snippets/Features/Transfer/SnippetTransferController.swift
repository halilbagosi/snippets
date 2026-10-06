import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Runs import and export end to end: save/open panels, file I/O, the
/// Finder-style conflict alert, and the message ContentView shows as a toast.
/// The rules live in the UI-free `SnippetArchive`, `SnippetExporter` and
/// `SnippetImporter`; this type only connects them to AppKit.
@MainActor
@Observable
final class SnippetTransferController {
    static let shared = SnippetTransferController()

    struct Notice: Equatable {
        let id = UUID()
        let message: String
    }

    /// The latest result, for ContentView's toast. Cleared once shown.
    private(set) var notice: Notice?

    /// The app's live trust store (set by `SnippetsApp`). A second instance
    /// would hold stale in-memory approvals, so replaced snippets must be
    /// forgotten through this one.
    @ObservationIgnored var previewTrust: PreviewTrust?

    @ObservationIgnored private var isImporting = false

    private var context: ModelContext { SnippetsData.sharedModelContainer.mainContext }
    private var media: MediaManager { .shared }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func clearNotice() { notice = nil }

    // MARK: Export

    func exportLibrary() {
        do {
            export(snippets: try context.fetch(FetchDescriptor<Snippet>()),
                   collections: try context.fetch(FetchDescriptor<SnippetCollection>()),
                   suggestedName: "Snippets Library")
        } catch {
            report(error, doing: "export")
        }
    }

    func exportCollection(_ collection: SnippetCollection) {
        export(snippets: [], collections: [collection], suggestedName: collection.name)
    }

    func exportSnippets(_ snippets: [Snippet], collections: [SnippetCollection] = []) {
        let name = switch (snippets.count, collections.count) {
        case (1, 0): snippets[0].title
        case (0, 1): collections[0].name
        default: "Snippets"
        }
        export(snippets: snippets, collections: collections, suggestedName: name)
    }

    private func export(snippets: [Snippet], collections: [SnippetCollection], suggestedName: String) {
        // Cheap check first: building the archive reads every attachment, so
        // it waits until the user has picked a destination.
        guard snippets.contains(where: { !$0.isDeleted }) || collections.contains(where: { !$0.isDeleted }) else {
            notice = Notice(message: "Nothing to export")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.snippetsArchive]
        panel.nameFieldStringValue = Self.fileName(for: suggestedName)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var missingAttachments = 0
        let media = media
        let archive = SnippetExporter.archive(snippets: snippets, collections: collections,
                                              appVersion: appVersion) { item in
            let data = media.data(for: item)
            if data == nil { missingAttachments += 1 }
            return data
        }
        guard !archive.snippets.isEmpty || !archive.collections.isEmpty else {
            notice = Notice(message: "Nothing to export")
            return
        }

        do {
            try context.save()   // keeps any uuid the exporter just assigned
            try archive.encoded().write(to: url, options: .atomic)
            notice = Notice(message: Self.exportMessage(snippetCount: archive.snippets.count,
                                                        missingAttachments: missingAttachments))
        } catch {
            report(error, doing: "export")
        }
    }

    /// "Exported 5 snippets", plus " · 2 attachments missing" when files the
    /// library still lists could not be read and so are not in the archive.
    static func exportMessage(snippetCount: Int, missingAttachments: Int) -> String {
        var message = "Exported \(snippetCount) \(snippetCount == 1 ? "snippet" : "snippets")"
        if missingAttachments > 0 {
            message += " · \(missingAttachments) \(missingAttachments == 1 ? "attachment" : "attachments") missing"
        }
        return message
    }

    static func fileName(for suggested: String) -> String {
        let cleaned = suggested
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (cleaned.isEmpty ? "Snippets" : cleaned) + ".snippets"
    }

    // MARK: Import

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.snippetsArchive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(at: url)
    }

    /// Shared by the open panel and by files opened from Finder or AirDrop.
    func importFile(at url: URL) {
        guard !isImporting else {
            NSSound.beep()
            return
        }
        isImporting = true
        // The toast and the conflict sheet both need the main window.
        MainWindowOpener.activate()

        let media = media
        Task {
            defer { isImporting = false }
            do {
                let archive = try await Self.loadArchive(from: url)
                let importer = SnippetImporter(
                    writeMedia: { data, ext in try media.storeImported(data, fileExtension: ext) },
                    removeMedia: { name in media.deleteFile(named: name) },
                    forgetTrust: { [self] id in previewTrust?.forget(id) }
                )
                let summary = try await importer.apply(archive, to: context) { [self] conflict in
                    await ask(conflict)
                }
                notice = Notice(message: summary.message)
            } catch {
                report(error, doing: "import")
            }
        }
    }

    /// Reads and validates the file off the main actor: an archive can be
    /// hundreds of MB, and decoding it on main would freeze the UI.
    @concurrent
    private nonisolated static func loadArchive(from url: URL) async throws -> SnippetArchive {
        // Files opened from Finder arrive security-scoped in the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= SnippetArchive.maxByteCount else { throw SnippetArchive.ReadError.tooLarge }
        return try SnippetArchive.decode(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Finder's "an item named … already exists" prompt. Skip is the default
    /// (Return) because it is the one choice that cannot lose anything;
    /// Escape stops.
    private func ask(_ conflict: ImportConflict) async -> ConflictResolution {
        let alert = NSAlert()
        let title = conflict.title.isEmpty ? "Untitled" : conflict.title
        alert.messageText = "A snippet named “\(title)” already exists in your library."
        alert.informativeText = conflict.isInTrash
            ? "It's in Recently Deleted. Replacing it puts the imported version back in your library."
            : "Replacing it overwrites your copy with the imported one."
        alert.addButton(withTitle: "Skip")
        let replace = alert.addButton(withTitle: "Replace")
        replace.hasDestructiveAction = true
        let stop = alert.addButton(withTitle: "Stop")
        stop.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Apply to all"

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        let choice: ConflictChoice = switch response {
        case .alertFirstButtonReturn: .skip
        case .alertSecondButtonReturn: .replace
        default: .stop
        }
        return ConflictResolution(choice: choice, applyToAll: alert.suppressionButton?.state == .on)
    }

    private func report(_ error: Error, doing action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = action == "import" ? "Couldn't import snippets" : "Couldn't export snippets"
        // Both failure paths are all-or-nothing: a bad file is rejected before
        // anything is written, and a failed apply rolls itself back.
        alert.informativeText = action == "import"
            ? "\(error.localizedDescription)\n\nNothing was changed."
            : error.localizedDescription
        alert.runModal()
    }
}
