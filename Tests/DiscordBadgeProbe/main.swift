import AppKit
import ApplicationServices
func value<T>(_ e: AXUIElement, _ key: String) -> T? { WindowService.value(e, key) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let service = DockBadgeService()
service.scan { badges in
    let badge = badges?["/Applications/Discord.app"] ?? "nil"
    print("Trusted: \(AXIsProcessTrusted()); service Discord: \(badge)")
    DispatchQueue.global().async {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { exit(2) }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var pending = [root]
        for _ in 0..<4 {
            var next: [AXUIElement] = []
            for item in pending {
                let title: String = value(item, kAXTitleAttribute) ?? ""
                if title.lowercased().contains("discord") {
                    var names: CFArray?
                    AXUIElementCopyAttributeNames(item, &names)
                    print("Discord attributes: \(names as? [String] ?? [])")
                    for key in [kAXTitleAttribute, kAXURLAttribute, "AXStatusLabel", kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
                        var result: CFTypeRef?
                        let error = AXUIElementCopyAttributeValue(item, key as CFString, &result)
                        print("\(key): code=\(error.rawValue), value=\(String(describing: result))")
                    }
                }
                next += (value(item, kAXChildrenAttribute) as [AXUIElement]?) ?? []
            }
            pending = next
        }
        for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier?.lowercased().contains("discord") == true {
            print("Running Discord URL: \(running.bundleURL?.path ?? "nil")")
        }
        fflush(stdout)
        DispatchQueue.main.async { app.terminate(nil) }
    }
}
app.run()
