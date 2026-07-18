import AppKit
import SwiftUI

/// Hosts the SwiftUI content but only accepts mouse events that fall inside the
/// currently "active" rect (the collapsed strip or the expanded panel). Clicks
/// on the transparent margins pass through to whatever is behind the window.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Returns the active rect in this view's coordinate space. Updated by the
    /// controller as the notch expands/collapses.
    var activeRectProvider: (() -> CGRect)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space.
        let local = superview.map { convert(point, from: $0) } ?? point
        guard let rect = activeRectProvider?(), rect.contains(local) else {
            return nil
        }
        return super.hitTest(point)
    }
}
