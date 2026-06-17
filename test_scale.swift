import AppKit

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
if let close = window.standardWindowButton(.closeButton) {
    close.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
    print("Scaled close button")
}
