import AppKit
import SwiftUI

/// Hosts the SwiftUI content but only accepts mouse events that fall inside the
/// currently "active" rect (the collapsed strip or the expanded panel). Clicks
/// on the transparent margins pass through to whatever is behind the window.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Returns the active rect in this view's coordinate space. Updated by the
    /// controller as the notch expands/collapses.
    var activeRectProvider: (() -> CGRect)?

    /// Two-finger swipes on the notch. Returns whether the event was used;
    /// anything it passes on goes to SwiftUI as usual. A list that scrolls
    /// is its own scroll view and gets its events before they reach here, so
    /// swipes and scrolling don't compete.
    var onScroll: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }

    /// A file drag over the surface: its location in this view's
    /// coordinates, or nil once it leaves or lands. SwiftUI's own drop
    /// targets (the shelf) still get everything — this only watches.
    var onDragMoved: ((CGPoint?) -> Void)?
    /// A drag finished over the surface; true when something accepted it.
    var onDropped: ((Bool) -> Void)?

    /// Files are always welcome, even while no SwiftUI drop target is on
    /// screen: the collapsed strip has none, and it's where a drag arrives.
    /// SwiftUI registers and unregisters its own types as drop targets come
    /// and go, so file URLs are folded back in each time.
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        super.registerForDraggedTypes(Array(Set(newTypes + [.fileURL])))
    }

    override func unregisterDraggedTypes() {
        super.unregisterDraggedTypes()
        super.registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(convert(sender.draggingLocation, from: nil))
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(convert(sender.draggingLocation, from: nil))
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragMoved?(nil)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let accepted = super.performDragOperation(sender)
        onDropped?(accepted)
        onDragMoved?(nil)
        return accepted
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space.
        let local = superview.map { convert(point, from: $0) } ?? point
        guard let rect = activeRectProvider?(), rect.contains(local) else {
            return nil
        }
        return super.hitTest(point)
    }
}
