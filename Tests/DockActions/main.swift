import AppKit
import ApplicationServices
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let bridge = DockMenuBridge()
let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
let ax = AXUIElementCreateApplication(finder.processIdentifier)
AXUIElementSetMessagingTimeout(ax, 0.3)
func windows() -> [AXUIElement] { WindowService.value(ax, kAXWindowsAttribute) ?? [] }
let before = windows()
print("Finder windows before test: \(before.count)")
bridge.load(url) { entries in
    // Finder exposes its own localized menu titles; support both system languages.
    guard let action = entries.first(where: { $0.title == "Nouvelle fenêtre Finder" || $0.title == "New Finder Window" }) else {
        print("FAIL no new Finder window action; entries=\(entries.count)")
        fflush(stdout); exit(2)
    }
    print("PASS: menu snapshot contains real Finder action (\(entries.count) entries)")
    bridge.perform(action.path, for: url) { success in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let after = windows()
            let delta = after.count - before.count
            print("Action accepted: \(success); window-count delta: \(delta)")
            // AX references may be recreated by Finder when opening a window.
            // The new window is focused; do not infer creation from CFEqual.
            if success && delta == 1,
               let focused: AXUIElement = WindowService.value(ax, kAXFocusedWindowAttribute),
               let close: AXUIElement = WindowService.value(focused, kAXCloseButtonAttribute) {
                print("Test window cleanup: \(AXUIElementPerformAction(close, kAXPressAction as CFString).rawValue)")
            }
            fflush(stdout)
            if !success || delta != 1 { exit(3) }
            app.terminate(nil)
        }
    }
}
app.run()
