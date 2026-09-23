import AppKit
import ApplicationServices

/// Opt-in integration harness: --terminal-zoom-test. Only touches its own new
/// Terminal window, identified by a random marker. No commands run in user tabs.
final class TerminalZoomTest {
    private let marker = "MacBarZoomTest-" + UUID().uuidString.prefix(8)
    private var script: URL!
    private var window: AXUIElement?
    private var baseline = CGRect.zero
    private var timer: Timer?
    private var started = Date()
    private var step = 0
    private var waiting = false
    private var previous = CGRect.null

    func start() {
        guard AXIsProcessTrusted() else { print("BLOCKED: Accessibility is not authorized"); NSApp.terminate(nil); return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(marker, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            script = directory.appendingPathComponent(marker + ".command")
            let command = "#!/bin/zsh\nprintf '\\033]0;" + marker + "\\007'\nfor attempt in {1..300}; do\n  [[ -f \"$0.done\" ]] && exit 0\n  /bin/sleep 0.2\ndone\n"
            try command.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open([script], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init()) { _, error in
                if let error { print("Terminal launch failed: \(error)") }
            }
            started = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        } catch { print("FAIL: \(error)"); NSApp.terminate(nil) }
    }

    private func tick() {
        if window == nil {
            guard Date().timeIntervalSince(started) < 15 else { finish("FAIL: test window not found"); return }
            guard let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first else { return }
            let app = AXUIElementCreateApplication(terminal.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            let windows: [AXUIElement] = WindowService.value(app, kAXWindowsAttribute) ?? []
            for candidate in windows {
                AXUIElementSetMessagingTimeout(candidate, 0.2)
                let title: String = WindowService.value(candidate, kAXTitleAttribute) ?? ""
                guard title.contains(marker) else { continue }
                window = candidate
                var size = CGSize(width: 900, height: 600)
                var point = CGPoint(x: 150, y: 160)
                if let value = AXValueCreate(.cgSize, &size) { _ = AXUIElementSetAttributeValue(candidate, kAXSizeAttribute as CFString, value) }
                if let value = AXValueCreate(.cgPoint, &point) { _ = AXUIElementSetAttributeValue(candidate, kAXPositionAttribute as CFString, value) }
                terminal.activate(options: [.activateIgnoringOtherApps])
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let frame = WindowFitter.frame(of: candidate) else { self.finish("FAIL: missing baseline"); return }
                    self.baseline = frame
                    print("BASELINE: \(frame)")
                    self.doubleClick()
                }
                return
            }
            return
        }
        guard waiting, let window, let frame = WindowFitter.frame(of: window), let screen = NSScreen.screens.first else { return }
        if frame != previous { print("STEP \(step) FRAME: \(frame)"); previous = frame }
        let primaryTop = screen.frame.maxY
        let cutoff = primaryTop - TaskLayout.frame(screen: screen.frame, visible: screen.visibleFrame).maxY
        let top = primaryTop - screen.visibleFrame.maxY
        let passed = step % 2 == 1
            ? abs(frame.minY - top) <= 32 && frame.maxY <= cutoff + 1 && frame.maxY >= cutoff - 64 && frame.height > baseline.height + 80
            : abs(frame.minX - baseline.minX) <= 2 && abs(frame.minY - baseline.minY) <= 2
                && abs(frame.width - baseline.width) <= 8 && abs(frame.height - baseline.height) <= 2
        if passed {
            waiting = false
            print("PASS \(step): \(step % 2 == 1 ? "Terminal titlebar double-click maximized above bar" : "Terminal titlebar double-click restored original size")")
            if step == 6 { finish("PASS: all 6 real Terminal titlebar transitions"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.doubleClick() }
        } else if Date().timeIntervalSince(started) > 8 { finish("FAIL: transition \(step), actual=\(frame), baseline=\(baseline)") }
    }

    private func doubleClick() {
        guard let window, let frame = WindowFitter.frame(of: window) else { finish("FAIL: test window disappeared"); return }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let point = CGPoint(x: frame.midX, y: frame.minY + 12)
        step += 1
        started = Date()
        waiting = true
        previous = .null
        // Actual titlebar mouse input respects AppleActionOnDoubleClick=Maximize.
        for (index, type) in [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: index < 2 ? 1 : 2)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func finish(_ message: String) {
        print(message)
        timer?.invalidate()
        waiting = false
        // Tell our test shell to exit before closing its own window.
        if let script { FileManager.default.createFile(atPath: script.path + ".done", contents: Data()) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let window = self.window, let button: AXUIElement = WindowService.value(window, kAXCloseButtonAttribute) {
                _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
            NSApp.terminate(nil)
        }
    }
}
