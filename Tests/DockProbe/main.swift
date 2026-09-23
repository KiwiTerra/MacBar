import AppKit
import ApplicationServices
func value<T>(_ e: AXUIElement, _ key: String) -> T? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, key as CFString, &result) == .success else { return nil }
    return result as? T
}
func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) ?? [] }
func walk(_ e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 4 else { return [] }
    return [e] + children(e).flatMap { walk($0, depth: depth + 1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.global().async {
    print("Trusted: \(AXIsProcessTrusted())")
    guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { exit(2) }
    let root = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.4)
    let items = walk(root)
    guard let target = items.first(where: { (value($0, kAXTitleAttribute) as String?) == "Finder" }) else { print("Finder not found"); exit(3) }
    var names: CFArray?
    AXUIElementCopyAttributeNames(target, &names)
    print("Dock item attributes: \(names as? [String] ?? [])")
    var actions: CFArray?
    AXUIElementCopyActionNames(target, &actions)
    print("Dock item actions: \(actions as? [String] ?? [])")
    print("Before children: \(children(target).count)")
    print("Show menu: \(AXUIElementPerformAction(target, kAXShowMenuAction as CFString).rawValue)")
    Thread.sleep(forTimeInterval: 0.2)
    let elements = walk(root) + walk(target)
    let menus = elements.filter { (value($0, kAXRoleAttribute) as String?) == kAXMenuRole }
    print("Menus: \(menus.count)")
    for menu in menus.prefix(1) {
        for item in children(menu) {
            let title: String = value(item, kAXTitleAttribute) ?? ""
            var a: CFArray?
            AXUIElementCopyActionNames(item, &a)
            print("Item: \(title), actions=\(a as? [String] ?? [])")
        }
        print("Cancel: \(AXUIElementPerformAction(menu, kAXCancelAction as CFString).rawValue)")
        Thread.sleep(forTimeInterval: 0.1)
        print("After cancel children: \(children(menu).count)")
    }
    fflush(stdout)
    DispatchQueue.main.async { app.terminate(nil) }
}
app.run()
