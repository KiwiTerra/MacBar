import AppKit
import SwiftUI
import ApplicationServices

final class BarModel: ObservableObject {
    @Published var badges: [String: String] = [:]
    private let badgeService = DockBadgeService()
    func badge(for url: URL) -> String? { badges[url.standardizedFileURL.path] }
    @Published var tasks: [TaskEntry] = []
    @Published var applications: [ApplicationEntry] = []
    @Published var trusted = AXIsProcessTrusted()
    @Published var clock = Date()
    @Published var error: String?
    @Published var loadingApplications = true
    @Published var grouped: Bool
    @Published var allScreens: Bool
    let preferences: Preferences
    private let service = WindowService()
    private var running: [RunningEntry] = []
    private var pins: [ApplicationEntry]
    private var appOrder: [String]
    @Published var draggedURL: URL?
    @Published var dropTarget: String?
    @Published var dropAfter = false
    private var pinOnDrop = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastCatalogScan = Date.distantPast
    var showLauncher: (() -> Void)?
    var showSettings: (() -> Void)?
    var showAppMenu: ((TaskEntry) -> Void)?
    var showWindows: ((TaskEntry) -> Void)?
    var screensChanged: (() -> Void)?
    var hoverTask: ((TaskEntry, Bool) -> Void)?
    var dismissPreviews: (() -> Void)?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        grouped = preferences.grouped
        allScreens = preferences.allScreens
        pins = preferences.pins
        appOrder = preferences.appOrder
        rebuild()
    }

    func start() {
        refresh()
        loadApplications()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.clock = Date()
            self?.refresh()
        }
        timer?.tolerance = 0.3
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    func refresh() {
        badgeService.scan { [weak self] badges in
            guard let self, let badges, self.badges != badges else { return }
            self.badges = badges
        }
        service.scan { [weak self] apps, trusted in
            guard let self else { return }
            self.running = apps
            self.trusted = trusted
            self.rebuild()
        }
    }
    private func rebuild() {
        let base = TaskLayout.entries(running: running, pins: pins, grouped: grouped, windowsAccessible: trusted)
        let reconciled = AppOrdering.reconcile(appOrder, visible: base.map { $0.url.path })
        if reconciled != appOrder { appOrder = reconciled; preferences.appOrder = appOrder }
        let ranks = Dictionary(uniqueKeysWithValues: appOrder.enumerated().map { ($1, $0) })
        tasks = base.enumerated().sorted {
            let left = ranks[$0.element.url.path] ?? Int.max
            let right = ranks[$1.element.url.path] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
    func toggleGrouping() {
        grouped.toggle()
        preferences.grouped = grouped
        rebuild()
    }
    func toggleScreens() {
        allScreens.toggle()
        preferences.allScreens = allScreens
        screensChanged?()
    }
    func isPinned(_ url: URL) -> Bool { pins.contains { $0.url == url } }
    func togglePin(_ url: URL) {
        if isPinned(url) { pins.removeAll { $0.url == url } }
        else { pins.append(ApplicationEntry(url: url, name: ApplicationCatalog.name(for: url))) }
        preferences.pins = pins
        rebuild()
        objectWillChange.send()
    }
    func beginDrag(_ url: URL, pin: Bool = false) {
        dismissPreviews?()
        draggedURL = url
        pinOnDrop = pin
    }
    func endDrag() { draggedURL = nil; dropTarget = nil; pinOnDrop = false }
    func drop(_ url: URL, relativeTo target: URL?, after: Bool, external: Bool = false) {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", Bundle(url: url) != nil else { endDrag(); return }
        if (external || pinOnDrop) && !isPinned(url) {
            pins.append(ApplicationEntry(url: url, name: ApplicationCatalog.name(for: url)))
            preferences.pins = pins
        }
        appOrder = AppOrdering.moving(url.path, relativeTo: target?.path, after: after, in: appOrder)
        preferences.appOrder = appOrder
        endDrag()
        rebuild()
    }
    func move(_ task: TaskEntry, direction: Int) {
        let visible = AppOrdering.reconcile([], visible: tasks.map { $0.url.path })
        guard let index = visible.firstIndex(of: task.url.path), visible.indices.contains(index + direction) else { return }
        appOrder = AppOrdering.moving(task.url.path, relativeTo: visible[index + direction], after: direction > 0, in: appOrder)
        preferences.appOrder = appOrder
        rebuild()
    }
    func click(_ task: TaskEntry) {
        dismissPreviews?()
        endDrag()
        if task.window == nil { service.toggleApplication(task, completion: completed) }
        else { service.select(task, completion: completed) }
    }
    func select(_ window: WindowEntry, in task: TaskEntry, forceRaise: Bool = true) {
        let entry = TaskEntry(id: window.id, name: window.title, subtitle: task.subtitle, url: task.url,
            pid: task.pid, window: window, windows: task.windows, active: task.active, pinned: task.pinned)
        service.select(entry, forceRaise: forceRaise, completion: completed)
    }
    func open(_ url: URL) { service.open(url, completion: completed) }
    func close(_ window: WindowEntry) { service.close(window, completion: completed) }
    private func completed(_ message: String?) {
        error = message
        refresh()
    }
    func loadApplications() {
        guard Date().timeIntervalSince(lastCatalogScan) > 30 else { return }
        lastCatalogScan = Date()
        DispatchQueue.global(qos: .utility).async {
            let apps = ApplicationCatalog.discover()
            DispatchQueue.main.async { [weak self] in
                self?.applications = apps
                self?.loadingApplications = false
            }
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class IconCache {
    static let shared = IconCache()
    private var icons: [URL: NSImage] = [:]
    func icon(_ url: URL) -> NSImage {
        if let icon = icons[url] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url] = icon
        return icon
    }
}
