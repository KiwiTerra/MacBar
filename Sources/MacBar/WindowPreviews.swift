import AppKit
import SwiftUI
import ScreenCaptureKit
import ApplicationServices
import Combine

struct PreviewEntry: Identifiable {
    let window: WindowEntry
    let frame: CGRect?
    var id: String { window.id }
}

private final class CachedPreview: NSObject {
    let image: NSImage
    let created = Date()
    init(_ image: NSImage) { self.image = image }
}

final class WindowPreviewModel: ObservableObject {
    @Published var entries: [PreviewEntry] = []
    @Published var images: [String: NSImage] = [:]
    @Published var unavailable = Set<String>()
    @Published var captureAllowed = CGPreflightScreenCaptureAccess()
    @Published var loading = true
    private var visible = Set<String>()
    private var generation = UUID()
    private var timer: Timer?
    private var capturing = false
    private var refreshPending = false
    private var refreshScheduled = false
    private var task: TaskEntry?
    private let cache: NSCache<NSString, CachedPreview> = {
        let cache = NSCache<NSString, CachedPreview>()
        cache.countLimit = 24
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    func start(_ task: TaskEntry) {
        stop()
        self.task = task
        captureAllowed = CGPreflightScreenCaptureAccess()
        entries = task.windows.map { PreviewEntry(window: $0, frame: nil) }
        loading = false
        if captureAllowed {
            for entry in entries {
                if let cached = cache.object(forKey: entry.id as NSString), Date().timeIntervalSince(cached.created) < 5 {
                    images[entry.id] = cached.image
                }
            }
        } else { cache.removeAllObjects() }
        // Warm the first page while the short hover-intent delay elapses.
        visible = Set(entries.prefix(4).map(\.id))
        refresh()
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = task.windows.map { PreviewEntry(window: $0, frame: WindowFitter.frame(of: $0.element)) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.entries = entries
                self.refresh()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.2
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        generation = UUID()
        entries = []
        images = [:]
        visible = []
        unavailable = []
        task = nil
        capturing = false
        refreshPending = false
        refreshScheduled = false
    }
    func setVisible(_ id: String, _ isVisible: Bool) {
        if isVisible {
            guard visible.insert(id).inserted else { return }
            // Batch all cards appearing during the same layout pass.
            guard !refreshScheduled else { return }
            refreshScheduled = true
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.refreshScheduled = false
                self.refresh()
            }
        }
        else { visible.remove(id) }
    }
    func requestCapture() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    private func refresh() {
        captureAllowed = CGPreflightScreenCaptureAccess()
        guard captureAllowed, let task, let pid = task.pid, !visible.isEmpty else { return }
        if capturing { refreshPending = true; return }
        guard #available(macOS 14, *) else { unavailable.formUnion(visible); return }
        let token = generation
        let wanted = entries.filter { visible.contains($0.id) }
        capturing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token {
                    self.capturing = false
                    if self.refreshPending { self.refreshPending = false; self.refresh() }
                }
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard self.generation == token else { return }
                var candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.height > 40 }
                var captures: [Task<Void, Never>] = []
                for entry in wanted {
                    guard self.generation == token else { return }
                    let descriptors = candidates.map { PreviewCandidate(id: $0.windowID, title: $0.title ?? "", frame: $0.frame) }
                    guard let id = PreviewMatching.best(title: entry.window.title, frame: entry.frame, candidates: descriptors),
                          let index = candidates.firstIndex(where: { $0.windowID == id }) else {
                        self.unavailable.insert(entry.id)
                        continue
                    }
                    let window = candidates.remove(at: index)
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let scale = min(480 / max(window.frame.width, 1), 300 / max(window.frame.height, 1))
                    config.width = max(1, Int(window.frame.width * scale))
                    config.height = max(1, Int(window.frame.height * scale))
                    config.showsCursor = false
                    config.capturesAudio = false
                    config.ignoreShadowsSingleWindow = true
                    // Start every window capture before awaiting any result.
                    captures.append(Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                            guard self.generation == token else { return }
                            let preview = NSImage(cgImage: image, size: NSSize(width: config.width, height: config.height))
                            self.images[entry.id] = preview
                            self.cache.setObject(CachedPreview(preview), forKey: entry.id as NSString, cost: image.bytesPerRow * image.height)
                            self.unavailable.remove(entry.id)
                        } catch {
                            if self.generation == token { self.unavailable.insert(entry.id) }
                        }
                    })
                }
                for capture in captures { await capture.value }
            } catch {
                guard self.generation == token else { return }
                self.unavailable.formUnion(wanted.map(\.id))
            }
        }
    }
}

struct WindowPreviewView: View {
    let task: TaskEntry
    @ObservedObject var previews: WindowPreviewModel
    @ObservedObject var model: BarModel
    let width: CGFloat
    let hover: (Bool) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: IconCache.shared.icon(task.url)).resizable().frame(width: 20, height: 20)
                Text(ApplicationCatalog.name(for: task.url)).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                Spacer()
                Button(model.isPinned(task.url) ? "Unpin" : "Pin") { model.togglePin(task.url) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if !model.trusted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow window access to show your windows here.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Allow Window Access") { dismiss(); model.requestAccessibility() }.buttonStyle(.bordered)
                }
            } else if previews.entries.isEmpty {
                Button("Open \(ApplicationCatalog.name(for: task.url))") { dismiss(); model.open(task.url) }.buttonStyle(.bordered)
            } else {
                if !previews.captureAllowed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enable window thumbnails.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Enable Previews") { previews.requestCapture() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 10) {
                        ForEach(previews.entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.window.title).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Button { model.close(entry.window); dismiss() } label: {
                                        Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24)
                                    }.buttonStyle(.plain).help("Close this window").accessibilityLabel("Close \(entry.window.title)")
                                }
                                Button {
                                    dismiss()
                                    model.select(entry.window, in: task)
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25))
                                        if let image = previews.images[entry.id] {
                                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(3)
                                        } else {
                                            VStack(spacing: 8) {
                                                Image(nsImage: IconCache.shared.icon(task.url)).resizable().frame(width: 40, height: 40)
                                                Text(entry.window.minimized ? "Minimized window" : previews.captureAllowed ? (previews.unavailable.contains(entry.id) ? "Preview unavailable" : "Loading…") : "Show this window")
                                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                            }
                                        }
                                    }.frame(width: 220, height: 140).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Afficher \(entry.window.title)")
                            }.frame(width: 220)
                                .onAppear { previews.setVisible(entry.id, true) }
                                .onDisappear { previews.setVisible(entry.id, false) }
                        }
                    }.padding(.bottom, 5)
                }.frame(height: 178)
            }
        }
        .padding(14).frame(width: width)
        .background(Color(red: 0.105, green: 0.112, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .onHover(perform: hover)
    }
}

final class WindowPreviewController {
    private let model: BarModel
    private let previews = WindowPreviewModel()
    private var panel: TaskbarPanel?
    private var sizingSubscription: AnyCancellable?
    private var pending: DispatchWorkItem?
    private var closing: DispatchWorkItem?
    private var current: String?
    private var prepared: String?
    private var hoveredTask: String?
    private var appHovered = false
    private var panelHovered = false
    init(model: BarModel) { self.model = model }

    func hover(_ task: TaskEntry, entered: Bool) {
        if model.draggedURL != nil && NSEvent.pressedMouseButtons == 0 { model.endDrag() }
        guard model.draggedURL == nil else { hide(); return }
        if entered {
            hoveredTask = task.id
            appHovered = true
            closing?.cancel()
            pending?.cancel()
            if current != task.id || panel?.isVisible != true {
                panel?.orderOut(nil)
                sizingSubscription = nil
                current = nil
                panelHovered = false
                previews.start(task)
                prepared = task.id
            }
            let point = NSEvent.mouseLocation
            let item = DispatchWorkItem { [weak self] in self?.show(task, at: point) }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        } else {
            guard hoveredTask == task.id else { return }
            hoveredTask = nil
            appHovered = false
            pending?.cancel()
            if panel?.isVisible != true { previews.stop(); prepared = nil }
            scheduleClose()
        }
    }
    func hide() {
        pending?.cancel()
        closing?.cancel()
        sizingSubscription = nil
        panel?.orderOut(nil)
        previews.stop()
        current = nil
        prepared = nil
        hoveredTask = nil
        panelHovered = false
        appHovered = false
    }
    private func scheduleClose() {
        closing?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.appHovered, !self.panelHovered else { return }
            self.hide()
        }
        closing = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
    private func show(_ task: TaskEntry, at point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.screens.first else { return }
        if current == task.id && panel?.isVisible == true { return }
        current = task.id
        if prepared != task.id { previews.start(task); prepared = task.id }
        let width = PreviewLayout.width(windowCount: task.windows.count, available: screen.visibleFrame.width - 16)
        let host = ArrowHostingView(rootView: WindowPreviewView(task: task, previews: previews, model: model, width: width, hover: { [weak self] entered in
            guard let self else { return }
            self.panelHovered = entered
            if entered { self.closing?.cancel() } else { self.scheduleClose() }
        }, dismiss: { [weak self] in self?.hide() }))
        let size = host.fittingSize
        host.sizingOptions = [.intrinsicContentSize]
        let y = TaskLayout.frame(screen: screen.frame, visible: screen.visibleFrame).maxY + 8
        let frame = CGRect(x: max(screen.visibleFrame.minX + 8, min(point.x - width / 2, screen.visibleFrame.maxX - width - 8)),
                           y: y, width: width, height: max(90, size.height))
        let popup = TaskbarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        popup.title = "Previews — MacBar"
        popup.isReleasedWhenClosed = false
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = true
        popup.hidesOnDeactivate = false
        popup.level = .floating
        popup.collectionBehavior = [.canJoinAllSpaces, .transient]
        host.frame = CGRect(origin: .zero, size: frame.size)
        popup.contentView = host
        popup.setContentSize(frame.size)
        panel?.close()
        panel = popup
        popup.orderFrontRegardless()
        sizingSubscription = model.$trusted.combineLatest(previews.$captureAllowed)
            .sink { [weak popup, weak host] _ in
                // Read after SwiftUI has applied permission/banner changes.
                DispatchQueue.main.async {
                    guard let popup, let host else { return }
                    host.layoutSubtreeIfNeeded()
                    popup.setContentSize(CGSize(width: width, height: max(90, host.fittingSize.height)))
                }
            }
    }
}
