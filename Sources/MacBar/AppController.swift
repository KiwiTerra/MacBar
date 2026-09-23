import AppKit
import SwiftUI
import ServiceManagement

final class TaskbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

final class AppController: NSObject, NSApplicationDelegate {
    let model = BarModel()
    private let windowFitter = WindowFitter()
    private let dockMenus = DockMenuBridge()
    private var menuRequest = UUID()
    private var terminalTest: TerminalZoomTest?
    private lazy var previewController = WindowPreviewController(model: model)
    private var bars: [TaskbarPanel] = []
    private var launcher: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var screenObserver: NSObjectProtocol?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hidden = false
    private var lastLayoutSignature = ""
    private var layoutTimer: Timer?
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.showLauncher = { [weak self] in self?.toggleLauncher() }
        model.showSettings = { [weak self] in self?.showOptions() }
        model.showAppMenu = { [weak self] task in self?.showAppMenu(task) }
        model.showWindows = { [weak self] task in self?.showWindowMenu(task) }
        model.hoverTask = { [weak self] task, entered in self?.previewController.hover(task, entered: entered) }
        model.dismissPreviews = { [weak self] in self?.previewController.hide() }
        model.screensChanged = { [weak self] in self?.rebuildBars() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "MacBar")
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusClicked)
        statusItem?.button?.toolTip = "MacBar"
        rebuildBars()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildBars() }
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateFrames() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let launcher = self.launcher, launcher.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeLauncher()
                return nil
            }
            if event.type != .keyDown, event.window !== launcher { self.closeLauncher() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeLauncher()
            self?.previewController.hide()
        }
        model.start()
        windowFitter.workAreas = { [weak self] in self?.windowWorkAreas() ?? [] }
        if !smokeTest { windowFitter.start() }
        if CommandLine.arguments.contains("--terminal-zoom-test") {
            terminalTest = TerminalZoomTest()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.terminalTest?.start() }
        }
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.finishSmokeTest() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        layoutTimer?.invalidate()
        windowFitter.stop()
    }

    private var selectedScreens: [NSScreen] {
        model.allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }
    private func rebuildBars() {
        previewController.hide()
        bars.forEach { $0.close() }
        bars = selectedScreens.map { screen in
            let panel = TaskbarPanel(contentRect: TaskLayout.frame(screen: screen.frame, visible: screen.visibleFrame),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "MacBar"
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isMovable = false
            panel.contentView = ArrowHostingView(rootView: BarView(model: model))
            if !hidden { panel.orderFrontRegardless() }
            return panel
        }
        lastLayoutSignature = ""
        updateFrames()
    }
    private func updateFrames() {
        let screens = selectedScreens
        guard screens.count == bars.count else { rebuildBars(); return }
        let signature = screens.map { NSStringFromRect($0.visibleFrame) + NSStringFromRect($0.frame) }.joined()
        guard signature != lastLayoutSignature else { return }
        lastLayoutSignature = signature
        for (panel, screen) in zip(bars, screens) {
            panel.setFrame(TaskLayout.frame(screen: screen.frame, visible: screen.visibleFrame), display: true)
        }
        closeLauncher()
    }

    private func windowWorkAreas() -> [WindowWorkArea] {
        guard let primary = NSScreen.screens.first else { return [] }
        let withBar = selectedScreens
        return NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            let index = withBar.firstIndex { $0 === screen }
            let bar = index.flatMap { $0 < bars.count ? bars[$0] : nil }
            let bottom: CGFloat? = !hidden && bar != nil
                ? primary.frame.maxY - TaskLayout.frame(screen: screen.frame, visible: visible).maxY
                : nil
            return WindowWorkArea(
                screen: WindowWorkArea.accessibilityRect(screen.frame, primaryTop: primary.frame.maxY),
                visible: WindowWorkArea.accessibilityRect(visible, primaryTop: primary.frame.maxY),
                reservedBottom: bottom)
        }
    }

    private func toggleLauncher() {
        previewController.hide()
        if launcher?.isVisible == true { closeLauncher(); return }
        model.loadApplications()
        let mouse = NSEvent.mouseLocation
        let bar = bars.first { $0.frame.contains(mouse) } ?? bars.first
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first
        guard let screen else { return }
        let height = min(CGFloat(620), screen.visibleFrame.height - 90)
        let frame = NSRect(x: min(max(bar?.frame.minX ?? screen.visibleFrame.minX + 8, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - 448),
            y: (bar?.frame.maxY ?? screen.visibleFrame.minY + 64) + 10, width: 440, height: max(280, height))
        let panel = LauncherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Applications — MacBar"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = NSHostingView(rootView: LauncherView(model: model, dismiss: { [weak self] in self?.closeLauncher() }))
        launcher?.close()
        launcher = panel
        panel.makeKeyAndOrderFront(nil)
    }
    private func closeLauncher() { launcher?.orderOut(nil) }

    @objc private func statusClicked() { showOptions() }
    @objc private func invoke(_ sender: NSMenuItem) { (sender.representedObject as? MenuAction)?.action() }
    private func add(_ title: String, to menu: NSMenu, checked: Bool? = nil, key: String = "", action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = MenuAction(action)
        if let checked { item.state = checked ? .on : .off }
        menu.addItem(item)
    }
    private func showOptions() {
        previewController.hide()
        closeLauncher()
        let menu = NSMenu()
        let title = NSMenuItem(title: "MacBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        add("Applications…", to: menu) { [weak self] in self?.toggleLauncher() }
        menu.addItem(.separator())
        add("Group by Application", to: menu, checked: model.grouped) { [weak self] in self?.model.toggleGrouping() }
        add("Show on All Displays", to: menu, checked: model.allScreens) { [weak self] in self?.model.toggleScreens() }
        add(hidden ? "Show Taskbar" : "Hide Taskbar", to: menu) { [weak self] in
            guard let self else { return }
            self.previewController.hide()
            self.hidden.toggle()
            self.bars.forEach { self.hidden ? $0.orderOut(nil) : $0.orderFrontRegardless() }
            self.windowFitter.schedule()
        }
        add("Launch at Login", to: menu, checked: SMAppService.mainApp.status == .enabled) { [weak self] in
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { self?.showError("Unable to change launch at login: \(error.localizedDescription)") }
        }
        menu.addItem(.separator())
        add(model.trusted ? "Accessibility Settings…" : "Allow Window Control…", to: menu) { [weak self] in self?.model.requestAccessibility() }
        add("macOS Dock Settings…", to: menu) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
        }
        add("About MacBar…", to: menu) { [weak self] in
            let alert = NSAlert()
            alert.messageText = "MacBar"
            alert.informativeText = "A native taskbar for your Mac.\nVersion 0.2.10 · local, no account required.\n\nClick: select a window.\nRight-click: windows, favorites, and actions.\n\nTo place the bar at the bottom of the screen, enable automatic Dock hiding in macOS settings."
            alert.addButton(withTitle: "OK")
            self?.closeLauncher()
            alert.runModal()
        }
        menu.addItem(.separator())
        add("Quit MacBar", to: menu, key: "q") { NSApp.terminate(nil) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    private func showAppMenu(_ task: TaskEntry) {
        previewController.hide()
        closeLauncher()
        let point = NSEvent.mouseLocation
        let request = UUID()
        menuRequest = request
        dockMenus.load(task.url) { [weak self] entries in
            guard let self, self.menuRequest == request else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            func append(_ entries: [DockMenuEntry], to parent: NSMenu) {
                for entry in entries {
                    if entry.title.isEmpty { parent.addItem(.separator()); continue }
                    self.add(entry.title, to: parent, checked: entry.checked) { [weak self] in
                        self?.dockMenus.perform(entry.path, for: task.url) { success in
                            if !success { self?.model.error = "This Dock action is no longer available. Reopen the menu." }
                            self?.model.refresh()
                        }
                    }
                    let item = parent.items.last!
                    item.isEnabled = entry.enabled
                    if !entry.children.isEmpty {
                        let submenu = NSMenu()
                        submenu.autoenablesItems = false
                        append(entry.children, to: submenu)
                        item.submenu = submenu
                    }
                }
            }
            append(entries, to: menu)
            if entries.isEmpty {
                self.add("Open", to: menu) { self.model.open(task.url) }
                for window in task.windows {
                    self.add(window.title, to: menu) { self.model.select(window, in: task) }
                }
                if let pid = task.pid {
                    self.add("Quit Application", to: menu) { NSRunningApplication(processIdentifier: pid)?.terminate() }
                }
            }
            menu.addItem(.separator())
            self.add(self.model.isPinned(task.url) ? "Unpin from MacBar" : "Pin to MacBar", to: menu) { self.model.togglePin(task.url) }
            self.add("Move Left", to: menu) { self.model.move(task, direction: -1) }
            self.add("Move Right", to: menu) { self.model.move(task, direction: 1) }
            self.add("Show in Finder", to: menu) { NSWorkspace.shared.activateFileViewerSelecting([task.url]) }
            menu.popUp(positioning: nil, at: point, in: nil)
        }
    }

    private func showWindowMenu(_ task: TaskEntry) {
        let menu = NSMenu()
        for window in task.windows {
            add((window.minimized ? "Minimized · " : "") + window.title, to: menu,
                checked: task.active && window.focused && !window.minimized) { [weak self] in self?.model.select(window, in: task) }
        }
        menu.addItem(.separator())
        add(model.isPinned(task.url) ? "Unpin from Taskbar" : "Pin to Taskbar", to: menu) { [weak self] in self?.model.togglePin(task.url) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "MacBar"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }
    private func finishSmokeTest() {
        let report: [String: Any] = ["panels": bars.count, "tasks": model.tasks.count,
            "applications": model.applications.count, "accessibility": model.trusted,
            "grouped": model.grouped, "framesValid": bars.allSatisfy { $0.frame.width > 0 && $0.frame.height == 56 }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) { print(string) }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), index + 1 < CommandLine.arguments.count {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let view = bars.first?.contentView { try snapshot(view, to: directory.appendingPathComponent("bar.png")) }
                toggleLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    do {
                        if let view = self?.launcher?.contentView { try self?.snapshot(view, to: directory.appendingPathComponent("launcher.png")) }
                    } catch { fputs("Snapshot error: \(error)\n", stderr) }
                    NSApp.terminate(nil)
                }
                return
            } catch { fputs("Snapshot error: \(error)\n", stderr) }
        }
        NSApp.terminate(nil)
    }
    private func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
