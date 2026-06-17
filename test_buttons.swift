import AppKit

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
let close = window.standardWindowButton(.closeButton)
close?.controlSize = .large
print("Close button size after large: \(close?.frame.size)")
