import AppKit

/// Run while MacBar is installed, running and authorized. Uses AppKit's REAL
/// zoom toggle rather than manually assigning the maximized rectangle.
final class ZoomFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var timer: Timer?
    var started = Date()
    var step = 0
    var waiting = false
    var normal = NSRect.zero
    var expanded = NSRect.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { exit(2) }
        normal = screen.visibleFrame.insetBy(dx: screen.visibleFrame.width * 0.18, dy: screen.visibleFrame.height * 0.18)
        expanded = screen.visibleFrame
        expanded.origin.y += 56
        expanded.size.height -= 56
        window = NSWindow(contentRect: normal, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "MacBar — maximize / restore test"
        window.setFrame(normal, display: true)
        normal = window.frame
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.toggle() }
    }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        NSScreen.screens.first!.visibleFrame
    }
    func toggle() {
        step += 1
        started = Date()
        waiting = true
        window.performZoom(nil)
    }
    func check() {
        guard waiting else { return }
        let actual = window.frame
        let expected = step % 2 == 1 ? expanded : normal
        let matches = abs(actual.minX - expected.minX) <= 2 && abs(actual.minY - expected.minY) <= 2
            && abs(actual.width - expected.width) <= 2 && abs(actual.height - expected.height) <= 2
        if matches {
            waiting = false
            print("PASS \(step): \(step % 2 == 1 ? "maximize clears bar" : "restore exact original frame")")
            if step == 6 { NSApp.terminate(nil) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.toggle() } }
        } else if Date().timeIntervalSince(started) > 8 {
            print("FAIL \(step): actual=\(actual), expected=\(expected)")
            exit(1)
        }
    }
}
let application = NSApplication.shared
let fixture = ZoomFixture()
application.setActivationPolicy(.regular)
application.delegate = fixture
application.run()
