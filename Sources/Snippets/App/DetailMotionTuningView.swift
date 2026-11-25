#if DEBUG
import AppKit
import SwiftUI

/// Debug ▸ Detail Motion…: debug builds only.
struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Detail Motion…") {
                openWindow(id: DetailMotionTuningView.windowID)
            }
            .keyboardShortcut("m", modifiers: [.command, .option, .control])
            Button("Reset Detail Motion") {
                DetailMotionTuning.shared.reset()
            }
        }
    }
}

/// Live sliders for ``DetailMotionTuning``. Changes apply to the next open
/// or close of the detail card; nothing needs a relaunch.
struct DetailMotionTuningView: View {
    static let windowID = "debug-detail-motion"

    @Bindable private var tuning = DetailMotionTuning.shared
    @State private var didCopy = false

    var body: some View {
        Form {
            Section("Morph") {
                Toggle("Morph the gallery card into the detail card", isOn: $tuning.values.morph)
                row("Morph open", \.morphInDuration, 0.05...1, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Morph close", \.morphOutDuration, 0.05...1, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Detail fades in", \.morphFadeInDuration, 0.02...0.6, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Detail fades out", \.morphFadeOutDuration, 0.02...0.6, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Card fades out in", \.morphCardFadeOutDuration, 0.02...0.6, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Card fades back in", \.morphCardFadeInDuration, 0.02...0.6, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Close hands over after", \.morphCloseHandoverDelay, 0...0.4, format: "%.2fs")
                    .disabled(!tuning.values.morph)
                row("Card blur", \.morphCardBlur, 0...30, step: 0.5, format: "%.1fpt")
                    .disabled(!tuning.values.morph)
            }
            Section("Speed") {
                row("Slow motion", \.slowMotion, 0.25...10, step: 0.25, format: "%.2f×")
                row("Zoom in", \.zoomInDuration, 0.05...1, format: "%.2fs")
                row("Zoom out", \.zoomOutDuration, 0.05...1, format: "%.2fs")
                row("Fade in", \.fadeInDuration, 0.02...0.6, format: "%.2fs")
                row("Fade out", \.fadeOutDuration, 0.02...0.6, format: "%.2fs")
                row("Preview expand", \.expandDuration, 0.05...1, format: "%.2fs")
            }
            Section("Shape") {
                row("Start scale", \.startScale, 0.05...1, format: "%.2f")
                row("Bottom stretch", \.warp, 0...0.3, step: 0.005, format: "%.3f")
                row("Open blur", \.openBlur, 0...30, step: 0.5, format: "%.1fpt")
                row("Open blur clears in", \.blurInDuration, 0...0.4, format: "%.2fs")
                row("Close blur", \.closeBlur, 0...30, step: 0.5, format: "%.1fpt")
            }
            Section {
                HStack {
                    Button("Reset to Defaults") { tuning.reset() }
                        .disabled(tuning.values == .defaults)
                    Spacer()
                    Button(didCopy ? "Copied" : "Copy Values") { copyValues() }
                }
            } footer: {
                Text("Start scale and the zoom anchor apply to the zoom style only. Applies to the next time a snippet opens or closes. Copy Values puts the current set on the clipboard, ready to paste into `DetailMotionTuning.Values`.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(
        _ title: String,
        _ keyPath: WritableKeyPath<DetailMotionTuning.Values, Double>,
        _ range: ClosedRange<Double>,
        step: Double = 0.01,
        format: String
    ) -> some View {
        let isDefault = tuning.values[keyPath: keyPath] == DetailMotionTuning.Values.defaults[keyPath: keyPath]
        return LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $tuning.values[dynamicMember: keyPath], in: range, step: step)
                Text(String(format: format, tuning.values[keyPath: keyPath]))
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            Text(title)
                .fontWeight(isDefault ? .regular : .semibold)
        }
    }

    private func copyValues() {
        let v = tuning.values
        let text = """
        var slowMotion: Double = 1
        var morph: Bool = \(v.morph)
        var morphInDuration: Double = \(round(v.morphInDuration))
        var morphOutDuration: Double = \(round(v.morphOutDuration))
        var morphFadeInDuration: Double = \(round(v.morphFadeInDuration))
        var morphFadeOutDuration: Double = \(round(v.morphFadeOutDuration))
        var morphCardFadeOutDuration: Double = \(round(v.morphCardFadeOutDuration))
        var morphCardFadeInDuration: Double = \(round(v.morphCardFadeInDuration))
        var morphCloseHandoverDelay: Double = \(round(v.morphCloseHandoverDelay))
        var morphCardBlur: Double = \(round(v.morphCardBlur))
        var zoomInDuration: Double = \(round(v.zoomInDuration))
        var zoomOutDuration: Double = \(round(v.zoomOutDuration))
        var fadeInDuration: Double = \(round(v.fadeInDuration))
        var fadeOutDuration: Double = \(round(v.fadeOutDuration))
        var startScale: Double = \(round(v.startScale))
        var warp: Double = \(round(v.warp))
        var openBlur: Double = \(round(v.openBlur))
        var blurInDuration: Double = \(round(v.blurInDuration))
        var expandDuration: Double = \(round(v.expandDuration))
        var closeBlur: Double = \(round(v.closeBlur))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    private func round(_ value: Double) -> String {
        String(format: "%g", (value * 1000).rounded() / 1000)
    }
}
#endif
