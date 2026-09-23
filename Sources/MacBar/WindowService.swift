import AppKit
import ApplicationServices

final class WindowService {
    private let queue = DispatchQueue(label: "dev.local.MacBar.accessibility", qos: .userInitiated)
    private var recentWindows: [pid_t: String] = [:] // Confined to queue.
    private var busy = false // Accessed only from the main thread.

    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }

    func scan(completion: @escaping ([RunningEntry], Bool) -> Void) {
        guard !busy else { return }
        busy = true
        let trusted = AXIsProcessTrusted()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, URL, Bool)? in
            guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !app.isTerminated, let url = app.bundleURL else { return nil }
            return (app.processIdentifier, app.localizedName ?? ApplicationCatalog.name(for: url), url, app.isHidden)
        }
        queue.async {
            let livePIDs = Set(apps.map { $0.0 })
            self.recentWindows = self.recentWindows.filter { livePIDs.contains($0.key) }
            let entries = apps.map { pid, name, url, hidden -> RunningEntry in
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.12)
                var windows: [WindowEntry] = []
                var windowsKnown = false
                if trusted {
                    let focused: AXUIElement? = Self.value(app, kAXFocusedWindowAttribute)
                    let scanned: [AXUIElement]? = Self.value(app, kAXWindowsAttribute)
                    windowsKnown = scanned != nil
                    let elements = scanned ?? []
                    windows = elements.compactMap { element in
                        AXUIElementSetMessagingTimeout(element, 0.12)
                        let subrole: String = Self.value(element, kAXSubroleAttribute) ?? ""
                        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
                        return WindowEntry(id: "window:\(pid):\(CFHash(element))",
                            title: Self.value(element, kAXTitleAttribute) ?? name,
                            element: element, minimized: Self.value(element, kAXMinimizedAttribute) ?? false,
                            focused: focused.map { CFEqual($0, element) } ?? false)
                    }
                }
                if let focused = windows.first(where: { $0.focused && !$0.minimized }) { self.recentWindows[pid] = focused.id }
                return RunningEntry(windowsKnown: windowsKnown, hidden: hidden, pid: pid, name: name, url: url, windows: windows, active: pid == frontPID)
            }
            DispatchQueue.main.async {
                self.busy = false
                completion(entries, trusted)
            }
        }
    }

    /// Grouped taskbar click toggles application visibility, like Command-H.
    func toggleApplication(_ task: TaskEntry, completion: @escaping (String?) -> Void) {
        guard let pid = task.pid, let app = NSRunningApplication(processIdentifier: pid) else {
            open(task.url, completion: completion); return
        }
        if app.isHidden {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps])
            completion(nil)
        } else if app.isActive {
            hide(app, completion: completion)
        } else {
            // Bring the app forward immediately, without waiting behind an AX scan.
            app.activate(options: [.activateIgnoringOtherApps])
            if !task.windows.isEmpty { selectMostRecent(task, completion: completion) }
            else { completion(nil) }
        }
    }

    private func hide(_ app: NSRunningApplication, completion: @escaping (String?) -> Void) {
        _ = app.hide()
        // On this macOS version hide() may return false even though it succeeds.
        // Check the resulting state after AppKit processes the request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion(app.isHidden ? nil : "This application cannot be hidden.")
        }
    }

    func selectMostRecent(_ task: TaskEntry, completion: @escaping (String?) -> Void) {
        guard let pid = task.pid else { open(task.url, completion: completion); return }
        queue.async {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.12)
            // Read at click time rather than relying on the periodic scan.
            let focused: AXUIElement? = Self.value(application, kAXFocusedWindowAttribute)
            let focusedID = focused.flatMap { element in task.windows.first { CFEqual($0.element, element) }?.id }
            let window = RecentWindow.choose(task.windows, focusedID: focusedID, rememberedID: self.recentWindows[pid])
            let selected = TaskEntry(id: window?.id ?? task.id, name: window?.title ?? task.name,
                subtitle: task.subtitle, url: task.url, pid: pid, window: window, windows: task.windows,
                active: task.active, pinned: task.pinned)
            DispatchQueue.main.async { self.select(selected, forceRaise: true, completion: completion) }
        }
    }

    func select(_ task: TaskEntry, forceRaise: Bool = false, completion: @escaping (String?) -> Void) {
        guard let pid = task.pid, let app = NSRunningApplication(processIdentifier: pid) else {
            open(task.url, completion: completion)
            return
        }
        guard let window = task.window else {
            app.activate(options: [.activateIgnoringOtherApps])
            completion(nil)
            return
        }
        let wasActive = app.isActive
        if app.isHidden { app.unhide() }
        queue.async {
            let minimized: Bool = Self.value(window.element, kAXMinimizedAttribute) ?? false
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.25)
            AXUIElementSetMessagingTimeout(window.element, 0.25)
            let focused: AXUIElement? = Self.value(application, kAXFocusedWindowAttribute)
            let isFocused = focused.map { CFEqual($0, window.element) } ?? false
            let shouldHide = !forceRaise && wasActive && isFocused && !minimized
            if shouldHide {
                self.recentWindows[pid] = window.id
                DispatchQueue.main.async { self.hide(app, completion: completion) }
                return
            }
            if minimized { _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            if result == .success { self.recentWindows[pid] = window.id }
            DispatchQueue.main.async {
                app.unhide()
                app.activate(options: [.activateIgnoringOtherApps])
                completion(result == .success ? nil : "This window is not responding. Try again in a moment.")
            }
        }
    }

    func open(_ url: URL, completion: @escaping (String?) -> Void) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            DispatchQueue.main.async { completion(error.map { "Unable to open the application: \($0.localizedDescription)" }) }
        }
    }

    func close(_ window: WindowEntry, completion: @escaping (String?) -> Void) {
        queue.async {
            let button: AXUIElement? = Self.value(window.element, kAXCloseButtonAttribute)
            let result = button.map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
            DispatchQueue.main.async { completion(result == .success ? nil : "This window cannot be closed here.") }
        }
    }
}
