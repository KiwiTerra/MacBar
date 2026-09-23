import AppKit
import ApplicationServices

struct ApplicationEntry: Identifiable, Equatable {
    let url: URL
    let name: String
    var id: String { url.path }
}

struct WindowEntry: Identifiable {
    let id: String
    let title: String
    let element: AXUIElement
    let minimized: Bool
    let focused: Bool
}

struct RunningEntry: Identifiable {
    var windowsKnown = true
    var hidden = false
    let pid: pid_t
    let name: String
    let url: URL
    let windows: [WindowEntry]
    let active: Bool
    var id: String { url.path }
}

struct TaskEntry: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let url: URL
    let pid: pid_t?
    let window: WindowEntry?
    let windows: [WindowEntry]
    let active: Bool
    let pinned: Bool
    var running: Bool { pid != nil }
}

enum TaskLayout {
    static func entries(running: [RunningEntry], pins: [ApplicationEntry], grouped: Bool, windowsAccessible: Bool = true) -> [TaskEntry] {
        // An empty successful scan means no window; a failed/unauthorized scan is unknown.
        let running = running.filter { !windowsAccessible || !$0.windowsKnown || $0.hidden || !$0.windows.isEmpty }
        let pinIDs = Set(pins.map(\.id))
        let ordered = pins.compactMap { pin in running.first { $0.id == pin.id } }
            + running.filter { !pinIDs.contains($0.id) }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let closedPins = pins.filter { pin in !running.contains { $0.id == pin.id } }.map {
            TaskEntry(id: "pin:\($0.id)", name: $0.name, subtitle: "Open \($0.name)", url: $0.url,
                      pid: nil, window: nil, windows: [], active: false, pinned: true)
        }
        var runningTasks: [TaskEntry] = []
        for app in ordered {
            if grouped || app.windows.isEmpty {
                runningTasks.append(TaskEntry(id: "app:\(app.pid)", name: app.name,
                    subtitle: app.windows.isEmpty ? app.name : "\(app.name) · \(app.windows.count) windows",
                    url: app.url, pid: app.pid, window: nil, windows: app.windows,
                    active: app.active, pinned: pinIDs.contains(app.id)))
            } else {
                for window in app.windows {
                    runningTasks.append(TaskEntry(id: window.id, name: window.title.isEmpty ? app.name : window.title,
                        subtitle: app.name, url: app.url, pid: app.pid, window: window, windows: app.windows,
                        active: app.active && window.focused && !window.minimized, pinned: pinIDs.contains(app.id)))
                }
            }
        }
        // Favorites stay at the beginning, even when one is not running.
        return pins.flatMap { pin in
            closedPins.filter { $0.url == pin.url } + runningTasks.filter { $0.url == pin.url }
        } + runningTasks.filter { !pinIDs.contains($0.url.path) }
    }

    static func frame(screen: NSRect, visible: NSRect, height: CGFloat = 56) -> NSRect {
        let width = max(1, min(screen.width, visible.width))
        return NSRect(x: visible.midX - width / 2, y: visible.minY, width: width, height: height)
    }
}

final class Preferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var grouped: Bool {
        get { defaults.object(forKey: "grouped") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "grouped") }
    }
    var appOrder: [String] {
        get { defaults.stringArray(forKey: "appOrder") ?? [] }
        set { defaults.set(newValue, forKey: "appOrder") }
    }
    var allScreens: Bool {
        get { defaults.bool(forKey: "allScreens") }
        set { defaults.set(newValue, forKey: "allScreens") }
    }
    var pins: [ApplicationEntry] {
        get {
            (defaults.stringArray(forKey: "pins") ?? []).compactMap { path in
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return ApplicationEntry(url: url, name: ApplicationCatalog.name(for: url))
            }
        }
        set { defaults.set(newValue.map(\.id), forKey: "pins") }
    }
}

enum ApplicationCatalog {
    static func name(for url: URL) -> String {
        if let bundle = Bundle(url: url) {
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
    static func discover() -> [ApplicationEntry] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String: ApplicationEntry] = [:]
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker where url.pathExtension == "app" {
                guard Bundle(url: url)?.bundleIdentifier != "dev.local.MacBar" else { continue }
                found[url.path] = ApplicationEntry(url: url, name: name(for: url))
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func filter(_ apps: [ApplicationEntry], query: String) -> [ApplicationEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return apps.filter { app in words.allSatisfy { app.name.localizedStandardContains($0) } }
    }
}

/// Global Accessibility coordinates: origin at the upper-left of the primary display.
struct WindowWorkArea {
    let screen: CGRect
    let visible: CGRect
    let reservedBottom: CGFloat?

    static func accessibilityRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func fitted(_ window: CGRect, areas: [WindowWorkArea], fullScreen: Bool = false,
                       minimized: Bool = false) -> CGRect? {
        guard !fullScreen, !minimized, window.width >= 120, window.height >= 120 else { return nil }
        // Choose among ALL displays, including those with no bar.
        let intersections = areas.map { area -> (WindowWorkArea, CGFloat) in
            let intersection = area.screen.intersection(window)
            return (area, intersection.isNull ? 0 : intersection.width * intersection.height)
        }
        guard let (area, overlap) = intersections.max(by: { $0.1 < $1.1 }), overlap > 0,
              let bottom = area.reservedBottom else { return nil }
        // Only vertically maximized windows (including left/right half-screen tiles).
        // Do not fight the placement of smaller, manually positioned windows.
        guard abs(window.minY - area.visible.minY) <= 16,
              window.maxY >= area.visible.maxY - 64,
              window.maxY > bottom + 1, bottom - window.minY >= 120 else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width, height: bottom - window.minY)
    }
}

/// Tracks the user's normal frame separately from the native zoom frame. AX resizing
/// changes AppKit's notion of “zoomed”, so a second native zoom must restore our saved frame.
struct WindowZoomState {
    private(set) var normal: CGRect?
    private(set) var fitted: CGRect?
    private var pending: (source: CGRect, target: CGRect, restoring: Bool)?

    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    mutating func update(_ frame: CGRect, areas: [WindowWorkArea]) -> CGRect? {
        if let pending {
            // An unchanged source is a refused/delayed write, never a successful fit.
            if Self.matches(frame, pending.source) { return pending.target }
            let roundedSize = abs(frame.minX - pending.target.minX) <= 2
                && abs(frame.minY - pending.target.minY) <= 2
                && abs(frame.width - pending.target.width) <= 32
                && abs(frame.height - pending.target.height) <= 64
            let clearsBar = pending.restoring || frame.maxY <= pending.target.maxY + 1
            if Self.matches(frame, pending.target) || (roundedSize && clearsBar) {
                // Remember the actual grid-aligned frame (Terminal uses character cells),
                // not the requested pixel size, or the next zoom loses its restore state.
                if pending.restoring { normal = frame; fitted = nil }
                else { fitted = frame }
                self.pending = nil
                return nil
            }
            self.pending = nil
        }
        if let fitted, Self.matches(frame, fitted) { return nil }
        // On restart, a window fitted by the previous MacBar instance must not
        // become its own "small" restore frame. Its old normal bounds are unknown.
        if normal == nil && fitted == nil,
           let area = areas.first(where: { $0.screen.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
           let bottom = area.reservedBottom,
           abs(frame.minY - area.visible.minY) <= 16,
           frame.maxY <= bottom + 2, frame.maxY >= bottom - 64 {
            fitted = frame
            normal = CGRect(x: frame.minX + frame.width * 0.125,
                            y: frame.minY + frame.height * 0.125,
                            width: frame.width * 0.75, height: frame.height * 0.75)
            return nil
        }
        guard let target = WindowWorkArea.fitted(frame, areas: areas) else {
            normal = frame
            fitted = nil
            return nil
        }
        if let fitted, let normal,
           abs(fitted.minX - target.minX) <= 2, abs(fitted.minY - target.minY) <= 2,
           abs(fitted.width - target.width) <= 2 {
            pending = (frame, normal, true)
            return normal
        }
        // An app that was already maximized when MacBar started has no observed
        // user frame. Give it a sensible restore size instead of leaving it stuck.
        if normal == nil {
            normal = CGRect(x: target.minX + target.width * 0.125,
                            y: target.minY + target.height * 0.125,
                            width: target.width * 0.75, height: target.height * 0.75)
        }
        pending = (frame, target, false)
        return target
    }
}

enum AppOrdering {
    static func destination(x: CGFloat, itemWidth: CGFloat, count: Int) -> (Int, Bool) {
        let index = max(0, Int(x / itemWidth))
        return (min(index, count), index >= count || x - CGFloat(index) * itemWidth >= itemWidth / 2)
    }
    static func reconcile(_ saved: [String], visible: [String]) -> [String] {
        var seen = Set<String>()
        return (saved + visible).filter { seen.insert($0).inserted }
    }
    static func moving(_ source: String, relativeTo target: String?, after: Bool, in order: [String]) -> [String] {
        guard source != target else { return order }
        var result = order.filter { $0 != source }
        let index = target.flatMap { result.firstIndex(of: $0) }.map { $0 + (after ? 1 : 0) } ?? result.count
        result.insert(source, at: index)
        return result
    }
}

struct PreviewCandidate {
    let id: UInt32
    let title: String
    let frame: CGRect
}
enum PreviewMatching {
    static func best(title: String, frame: CGRect?, candidates: [PreviewCandidate]) -> UInt32? {
        let exact = candidates.filter { $0.title == title }
        let pool = exact.isEmpty ? candidates : exact
        guard let frame else { return pool.first?.id }
        return pool.min { a, b in
            func distance(_ rect: CGRect) -> CGFloat {
                abs(rect.minX - frame.minX) + abs(rect.minY - frame.minY)
                    + abs(rect.width - frame.width) + abs(rect.height - frame.height)
            }
            return distance(a.frame) < distance(b.frame)
        }?.id
    }
}

/// Card widths plus inter-card gaps and the two 14-point popup insets.
enum PreviewLayout {
    static func width(windowCount: Int, available: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, min(windowCount, 4)))
        return min(available, count * 220 + (count - 1) * 10 + 28)
    }
}

enum RecentWindow {
    static func choose(_ windows: [WindowEntry], focusedID: String?, rememberedID: String?) -> WindowEntry? {
        windows.first { $0.id == focusedID && !$0.minimized }
            ?? windows.first { $0.id == rememberedID }
            ?? windows.first { $0.id == focusedID }
            ?? windows.first { !$0.minimized }
            ?? windows.first
    }
}

enum DockBadge {
    static func normalized(_ label: String) -> String? {
        guard !label.isEmpty else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "•" : trimmed
    }
    static func display(_ label: String) -> String {
        if let number = Int(label), number > 99 { return "99+" }
        return label.count > 4 ? String(label.prefix(3)) + "…" : label
    }
}
