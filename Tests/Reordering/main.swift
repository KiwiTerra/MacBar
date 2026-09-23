import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let suite = "MacBar.Reordering.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let preferences = Preferences(defaults: defaults)
let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
let safari = URL(fileURLWithPath: "/Applications/Safari.app")
preferences.pins = [terminal, finder, safari].map { ApplicationEntry(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
let model = BarModel(preferences: preferences)
let panel = TaskbarPanel(contentRect: CGRect(x: 100, y: 300, width: 850, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
let host = ArrowHostingView(rootView: BarView(model: model))
panel.contentView = host
panel.orderFrontRegardless()
func findTracker(_ view: NSView) -> ReorderTrackingView? {
    if let result = view as? ReorderTrackingView { return result }
    return view.subviews.compactMap(findTracker).first
}
func send(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat = 28) {
    let tracker = findTracker(panel.contentView!)!
    let point = tracker.convert(CGPoint(x: x, y: y), to: nil)
    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    app.sendEvent(event)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    assert(!panel.isKeyWindow, "Fixture must exercise the non-key taskbar")
    host.updateTrackingAreas()
    assert(host.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.cursorUpdate) }, "Cursor tracking must stay active in a non-key panel")
    let movement = NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 300, y: 28), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
    NSCursor.resizeUpDown.set()
    host.cursorUpdate(with: movement)
    assert(NSCursor.current == NSCursor.arrow, "Entering from vertical resize restores arrow")
    NSCursor.resizeLeftRight.set()
    host.mouseMoved(with: movement)
    assert(NSCursor.current == NSCursor.arrow, "Mouse movement clears horizontal resize cursor")
    print("PASS: cursor restoration in non-key taskbar")
    send(.leftMouseDown, x: 23)
    send(.leftMouseDragged, x: 130)
    assert(model.draggedURL == terminal, "Drag must actually start through AppKit event routing")
    send(.leftMouseUp, x: 130)
    assert(model.tasks.map(\.url) == [finder, safari, terminal], "Drag first icon after third")
    send(.leftMouseDown, x: 115)
    send(.leftMouseDragged, x: 3)
    send(.leftMouseUp, x: 3)
    assert(model.tasks.map(\.url) == [terminal, finder, safari], "Drag last icon before first")
    send(.leftMouseDown, x: 23)
    send(.leftMouseDragged, x: 100, y: 120)
    send(.leftMouseUp, x: 100, y: 120)
    assert(model.tasks.map(\.url) == [terminal, finder, safari] && model.draggedURL == nil, "Release outside cancels without changing order")
    let reloaded = BarModel(preferences: Preferences(defaults: defaults))
    assert(reloaded.tasks.map(\.url) == [terminal, finder, safari], "Order survives model reload")
    defaults.removePersistentDomain(forName: suite)
    print("PASS: native non-key panel drag right, drag left, outside cancellation, persisted order")
    app.terminate(nil)
}
app.run()
