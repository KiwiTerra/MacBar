import AppKit
import ApplicationServices

final class DockBadgeService {
    private let queue = DispatchQueue(label: "dev.local.MacBar.dock-badges", qos: .utility)
    private var busy = false // Main-thread callers only.
    func scan(completion: @escaping ([String: String]?) -> Void) {
        guard !busy else { return }
        guard AXIsProcessTrusted() else { completion([:]); return }
        busy = true
        queue.async {
            var result: [String: String] = [:]
            guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
                DispatchQueue.main.async { self.busy = false; completion(nil) }; return
            }
            let root = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.12)
            guard let children: [AXUIElement] = WindowService.value(root, kAXChildrenAttribute) else {
                DispatchQueue.main.async { self.busy = false; completion(nil) }; return
            }
            var pending = children
            for _ in 0..<3 {
                var next: [AXUIElement] = []
                for item in pending {
                    AXUIElementSetMessagingTimeout(item, 0.12)
                    if let url: URL = WindowService.value(item, kAXURLAttribute), url.pathExtension.lowercased() == "app" {
                        if let label: String = WindowService.value(item, "AXStatusLabel"), let badge = DockBadge.normalized(label) {
                            result[url.standardizedFileURL.path] = badge
                        }
                        // Never open or traverse an application's Dock menu.
                    } else {
                        let children: [AXUIElement] = WindowService.value(item, kAXChildrenAttribute) ?? []
                        next += children
                    }
                }
                pending = next
            }
            DispatchQueue.main.async { self.busy = false; completion(result) }
        }
    }
}
