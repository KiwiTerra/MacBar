import AppKit
import ApplicationServices
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let service = WindowService()
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); fflush(stdout); exit(2) }
    print("PASS: \(message)")
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
NSWorkspace.shared.openApplication(at: url, configuration: .init()) { running, error in
    guard let running else { print("Launch failed"); exit(3) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        let ax = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        let windows: [AXUIElement] = WindowService.value(ax, kAXWindowsAttribute) ?? []
        check(windows.count == 2 && running.isActive, "two-window fixture is active before click")
        let task = TaskEntry(id: "hide-test", name: "Hide Test", subtitle: "", url: url, pid: running.processIdentifier, window: nil, windows: [], active: true, pinned: false)
        service.toggleApplication(task) { error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("State: error=\(String(describing: error)), hidden=\(running.isHidden), active=\(running.isActive), policy=\(running.activationPolicy.rawValue), currentHidden=\(NSRunningApplication(processIdentifier: running.processIdentifier)?.isHidden ?? false)")
                check(error == nil && running.isHidden, "taskbar click hides entire app")
                check(windows.allSatisfy { (WindowService.value($0, kAXMinimizedAttribute) as Bool?) == false }, "neither window uses native minimization")
                service.toggleApplication(task) { error in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        check(error == nil && !running.isHidden && running.isActive, "second click unhides and activates app")
                        check(windows.allSatisfy { (WindowService.value($0, kAXMinimizedAttribute) as Bool?) == false }, "both windows return without minimization")
                        running.terminate()
                        fflush(stdout)
                        app.terminate(nil)
                    }
                }
            }
        }
    }
}
app.run()
