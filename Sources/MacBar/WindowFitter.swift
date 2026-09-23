import AppKit
import ApplicationServices

/// Fits the active standard window after maximize/resize events, with a polling fallback
/// for applications that do not publish AX notifications. All AX calls are off the UI thread.
final class WindowFitter {
    var workAreas: (() -> [WindowWorkArea])?
    private let queue = DispatchQueue(label: "dev.local.MacBar.window-fit", qos: .userInitiated)
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var busy = false // Main thread only.
    private var stopped = false
    // Queue-confined observer state.
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private struct Record {
        let element: AXUIElement
        var state = WindowZoomState()
        var seen = Date()
    }
    private var records: [String: Record] = [:]
    private var lastAttempt: (pid: pid_t, window: CFHashCode, frame: CGRect, time: Date)?

    func start() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.schedule()
            }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 0.15
        schedule()
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        pending?.cancel()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        queue.sync { removeObserver() }
    }

    func schedule() {
        guard !stopped else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.check() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func check() {
        guard !stopped, !busy, NSEvent.pressedMouseButtons == 0,
              AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let areas = workAreas?() ?? []
        guard areas.contains(where: { $0.reservedBottom != nil }) else { return }
        busy = true
        let pid = app.processIdentifier
        queue.async { [weak self] in
            guard let self else { return }
            defer { DispatchQueue.main.async { self.busy = false } }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.15)
            guard let window: AXUIElement = WindowService.value(application, kAXFocusedWindowAttribute) else { return }
            AXUIElementSetMessagingTimeout(window, 0.15)
            self.observe(pid: pid, application: application, window: window)
            let role: String = WindowService.value(window, kAXSubroleAttribute) ?? ""
            guard role == kAXStandardWindowSubrole else { return }
            let fullscreen: Bool = WindowService.value(window, "AXFullScreen") ?? false
            let minimized: Bool = WindowService.value(window, kAXMinimizedAttribute) ?? false
            guard !fullscreen, !minimized, let frame = Self.frame(of: window) else { return }
            let key = "\(pid):\(CFHash(window))"
            var record = self.records[key].flatMap { CFEqual($0.element, window) ? $0 : nil } ?? Record(element: window)
            record.seen = Date()
            let planned = record.state.update(frame, areas: areas)
            self.records[key] = record
            if self.records.count > 128, let oldest = self.records.min(by: { $0.value.seen < $1.value.seen })?.key {
                self.records.removeValue(forKey: oldest)
            }
            if let last = self.lastAttempt, last.pid == pid, last.window == CFHash(window),
               !WindowZoomState.matches(last.frame, frame) { self.lastAttempt = nil }
            guard let target = planned else { return }
            // Apps can enforce a minimum height or refuse resizing: don't hammer them.
            if let last = self.lastAttempt, last.pid == pid, last.window == CFHash(window),
               last.frame == frame, Date().timeIntervalSince(last.time) < 3 { return }
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
                  settable.boolValue else { return }
            self.lastAttempt = (pid, CFHash(window), frame, Date())
            var size = target.size
            guard let value = AXValueCreate(.cgSize, &size) else { return }
            _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            if abs(target.minX - frame.minX) > 2 || abs(target.minY - frame.minY) > 2 {
                var point = target.origin
                if let position = AXValueCreate(.cgPoint, &point) {
                    _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
                }
            }
            // Restoring an observed frame should not accumulate character-grid rounding.
            // Compensate using the actual AX result rather than repeatedly requesting
            // the same size (Terminal can otherwise lose a few pixels per cycle).
            if abs(target.minX - frame.minX) > 2 || abs(target.minY - frame.minY) > 2 {
                var requested = target.size
                for _ in 0..<3 {
                    guard let actual = Self.frame(of: window),
                          !WindowZoomState.matches(actual, target),
                          abs(actual.width - target.width) <= 32,
                          abs(actual.height - target.height) <= 64 else { break }
                    requested.width += target.width - actual.width
                    requested.height += target.height - actual.height
                    guard requested.width >= 120, requested.height >= 120,
                          let calibrated = AXValueCreate(.cgSize, &requested) else { break }
                    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, calibrated)
                }
            }
            // A character-cell terminal can round a requested height upward.
            // Ask one rounding error lower so its bottom never covers the bar.
            if let actual = Self.frame(of: window),
               target.height < frame.height, abs(target.minY - frame.minY) <= 2,
               actual.height > target.height + 1, actual.height - target.height <= 64 {
                var floored = CGSize(width: target.width, height: target.height - (actual.height - target.height) - 1)
                if floored.height >= 120, let value = AXValueCreate(.cgSize, &floored) {
                    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
                }
            }
            if let actual = Self.frame(of: window), WindowZoomState.matches(actual, target) {
                _ = record.state.update(actual, areas: areas)
                self.records[key] = record
                self.lastAttempt = nil
            }
        }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position: AXValue = WindowService.value(window, kAXPositionAttribute),
              let size: AXValue = WindowService.value(window, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func observe(pid: pid_t, application: AXUIElement, window: AXUIElement) {
        if pid != observedPID {
            removeObserver()
            var created: AXObserver?
            let result = AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                let fitter = Unmanaged<WindowFitter>.fromOpaque(context).takeUnretainedValue()
                fitter.schedule() // Observer run-loop source is on the main run loop.
            }, &created)
            guard result == .success, let created else { return }
            observer = created
            observedPID = pid
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
                _ = AXObserverAddNotification(created, application, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        guard let observer else { return }
        if let old = observedWindow, CFEqual(old, window) { return }
        if let old = observedWindow {
            for name in [kAXWindowResizedNotification, kAXWindowMovedNotification] {
                _ = AXObserverRemoveNotification(observer, old, name as CFString)
            }
        }
        observedWindow = window
        for name in [kAXWindowResizedNotification, kAXWindowMovedNotification] {
            _ = AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func removeObserver() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedPID = nil
        observedWindow = nil
    }
}
