import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let windows = (0..<2).map { index -> NSWindow in
    let window = NSWindow(contentRect: CGRect(x: 140 + index * 50, y: 240, width: 340, height: 180), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "MacBar Hide Test \(index)"
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    return window
}
app.activate(ignoringOtherApps: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { app.terminate(nil) }
app.run()
