import AppKit
import SwiftUI

/// A non-key panel still needs an active tracking area to replace a cursor left
/// behind by another app's resize border. SwiftUI hover styling alone does not.
final class ArrowHostingView<Content: View>: NSHostingView<Content> {
    private var cursorTracking: NSTrackingArea?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
    override func updateTrackingAreas() {
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        super.updateTrackingAreas()
        let tracking = NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        cursorTracking = tracking
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: .arrow)
    }
    private func restoreArrow() {
        // Do not interfere with an ongoing resize/drag from another window.
        if NSEvent.pressedMouseButtons == 0 { NSCursor.arrow.set() }
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        restoreArrow()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        restoreArrow()
    }
    override func cursorUpdate(with event: NSEvent) { restoreArrow() }
}
