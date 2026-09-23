import AppKit
import ApplicationServices

struct DockMenuStep { let title: String; let occurrence: Int }
struct DockMenuEntry {
    let title: String
    let enabled: Bool
    let checked: Bool
    let path: [DockMenuStep]
    let children: [DockMenuEntry]
}

/// Dock menus only exist while open. Snapshot labels, then resolve a fresh path
/// on selection instead of keeping invalid AX menu-item references.
final class DockMenuBridge {
    private let queue = DispatchQueue(label: "dev.local.MacBar.dock-menu", qos: .userInitiated)
    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? { WindowService.value(element, attribute) }
    private func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) ?? [] }
    private func menu(of item: AXUIElement) -> AXUIElement? {
        if let shown: AXUIElement = value(item, "AXShownMenuUIElement") { return shown }
        return children(item).first { (value($0, kAXRoleAttribute) as String?) == kAXMenuRole }
    }
    private func dockItem(_ url: URL) -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var pending = [root]
        for _ in 0..<4 {
            var next: [AXUIElement] = []
            for item in pending {
                if let itemURL: URL = value(item, kAXURLAttribute), itemURL.standardizedFileURL == url.standardizedFileURL { return item }
                next += children(item)
            }
            pending = next
        }
        return nil
    }
    private func open(_ item: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(item, 0.3)
        _ = AXUIElementPerformAction(item, kAXShowMenuAction as CFString)
        for _ in 0..<10 {
            if let menu = menu(of: item), !children(menu).isEmpty { return menu }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return nil
    }
    private func snapshot(_ menu: AXUIElement, path: [DockMenuStep] = [], depth: Int = 0) -> [DockMenuEntry] {
        guard depth < 4 else { return [] }
        var counts: [String: Int] = [:]
        return children(menu).prefix(100).map { item in
            let title: String = value(item, kAXTitleAttribute) ?? ""
            let occurrence = counts[title, default: 0]
            counts[title] = occurrence + 1
            let next = path + [DockMenuStep(title: title, occurrence: occurrence)]
            let submenu = self.menu(of: item)
            return DockMenuEntry(title: title, enabled: value(item, kAXEnabledAttribute) ?? true,
                checked: !(value(item, kAXMenuItemMarkCharAttribute) as String? ?? "").isEmpty,
                path: next, children: submenu.map { snapshot($0, path: next, depth: depth + 1) } ?? [])
        }
    }
    func load(_ url: URL, completion: @escaping ([DockMenuEntry]) -> Void) {
        queue.async {
            guard AXIsProcessTrusted(), let item = self.dockItem(url), let menu = self.open(item) else {
                DispatchQueue.main.async { completion([]) }; return
            }
            let entries = self.snapshot(menu)
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            DispatchQueue.main.async { completion(entries) }
        }
    }
    func perform(_ path: [DockMenuStep], for url: URL, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard !path.isEmpty, let item = self.dockItem(url), let root = self.open(item) else {
                DispatchQueue.main.async { completion(false) }; return
            }
            var current = root
            var success = false
            defer {
                if !success { _ = AXUIElementPerformAction(root, kAXCancelAction as CFString) }
                DispatchQueue.main.async { completion(success) }
            }
            for (index, step) in path.enumerated() {
                let matches = self.children(current).filter { (self.value($0, kAXTitleAttribute) as String?) == step.title }
                guard matches.indices.contains(step.occurrence) else { return }
                let target = matches[step.occurrence]
                guard self.value(target, kAXEnabledAttribute) as Bool? != false else { return }
                if index == path.count - 1 {
                    success = AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
                } else {
                    guard let submenu = self.menu(of: target) else { return }
                    _ = AXUIElementPerformAction(target, kAXPressAction as CFString)
                    current = submenu
                }
            }
        }
    }
}
