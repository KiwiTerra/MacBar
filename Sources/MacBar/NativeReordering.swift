import AppKit
import SwiftUI

/// Track a press/drag/release in the row before SwiftUI's Button consumes it.
/// This does not start an NSDraggingSession, so it also works in a non-key panel.
struct NativeReordering: NSViewRepresentable {
    let model: BarModel
    func makeNSView(context: Context) -> ReorderTrackingView { ReorderTrackingView(model: model) }
    func updateNSView(_ view: ReorderTrackingView, context: Context) { view.model = model }
    static func dismantleNSView(_ view: ReorderTrackingView, coordinator: ()) { view.stop() }
}

final class ReorderTrackingView: NSView {
    var model: BarModel
    private var monitor: Any?
    private var pressed: TaskEntry?
    private var origin = CGPoint.zero
    private var dragging = false
    init(model: BarModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if pressed != nil { model.endDrag() }
        pressed = nil
        dragging = false
    }
    private func target(at point: CGPoint) -> (URL?, Bool) {
        let (index, after) = AppOrdering.destination(x: point.x, itemWidth: model.grouped ? 46 : 164, count: model.tasks.count)
        return (model.tasks.indices.contains(index) ? model.tasks[index].url : nil, after)
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53, pressed != nil {
            pressed = nil; dragging = false; model.endDrag()
            return nil
        }
        guard event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            guard visibleRect.contains(point) else { return event }
            let index = Int(point.x / (model.grouped ? 46 : 164))
            guard model.tasks.indices.contains(index) else { return event }
            model.showAppMenu?(model.tasks[index])
            return nil
        }
        if event.type == .leftMouseDown {
            guard visibleRect.contains(point) else { return event }
            let index = Int(point.x / (model.grouped ? 46 : 164))
            guard model.tasks.indices.contains(index) else { return event }
            pressed = model.tasks[index]
            origin = point
            dragging = false
            model.dismissPreviews?()
            return nil
        }
        guard let task = pressed else { return event }
        if event.type == .leftMouseDragged {
            if !dragging && hypot(point.x - origin.x, point.y - origin.y) >= 4 {
                dragging = true
                model.beginDrag(task.url)
            }
            if dragging {
                _ = autoscroll(with: event)
                let (url, after) = target(at: convert(event.locationInWindow, from: nil))
                model.dropTarget = url?.path ?? "end"
                model.dropAfter = after
            }
            return nil
        }
        if event.type == .leftMouseUp {
            pressed = nil
            let wasDragging = dragging
            dragging = false
            if wasDragging {
                if visibleRect.contains(point) {
                    let (url, after) = target(at: point)
                    model.drop(task.url, relativeTo: url, after: after)
                } else { model.endDrag() }
            } else if visibleRect.contains(point) { model.click(task) }
            return nil
        }
        return event
    }
}
