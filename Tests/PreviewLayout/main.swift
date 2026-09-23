import AppKit
import SwiftUI
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let model = BarModel()
model.trusted = true
let previews = WindowPreviewModel()
previews.captureAllowed = false
let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
let windows = (0..<2).map { WindowEntry(id: "fixture-\($0)", title: "A window with a particularly long title to check the width — \($0)", element: AXUIElementCreateApplication(getpid()), minimized: false, focused: false) }
previews.entries = windows.map { PreviewEntry(window: $0, frame: nil) }
let task = TaskEntry(id: "fixture", name: "Terminal", subtitle: "", url: url, pid: nil, window: nil, windows: windows, active: false, pinned: false)
let width = PreviewLayout.width(windowCount: windows.count, available: 1600)
let host = NSHostingView(rootView: WindowPreviewView(task: task, previews: previews, model: model, width: width, hover: { _ in }, dismiss: {}))
let size = host.fittingSize
host.sizingOptions = [.intrinsicContentSize]
let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 100, y: 300), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: size.height))
panel.contentView = host
panel.setContentSize(CGSize(width: width, height: size.height))
panel.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    host.layoutSubtreeIfNeeded()
    assert(abs(host.bounds.width - 478) < 1 && host.bounds.height > 200, "Two-window panel must fit both full cards")
    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("PASS two-window layout: \(host.bounds.size)")
    app.terminate(nil)
}
app.run()
