import AppKit

/// Describes the physical notch (or a simulated one) on a given screen and
/// derives the collapsed / expanded window frames used by the panel.
struct NotchMetrics {
    /// Size of the hardware notch itself, in screen points.
    let notchSize: CGSize
    /// The screen the notch belongs to.
    let screen: NSScreen
    /// Whether this screen has a real hardware notch.
    let hasHardwareNotch: Bool

    /// The collapsed strip drawn on screen. On notched Macs this hugs the
    /// hardware notch exactly, so the app is invisible until it expands.
    var collapsedSize: CGSize { notchSize }

    // Expanded panel dimensions.
    var expandedWidth: CGFloat { max(collapsedSize.width + 60, 640) }
    var expandedHeight: CGFloat { 250 }

    /// Transparent margin around the expanded panel (sides and bottom) so the
    /// drop shadow and ambient glow can fade out fully inside the window.
    /// Gaussian tails stay visible to roughly 3x their blur radius, so this
    /// must comfortably exceed that or the cut-off shows as a straight-edged
    /// block against bright wallpapers. The top stays flush with the screen
    /// edge so the collapsed strip aligns with the hardware notch.
    static let shadowMargin: CGFloat = 60

    /// Frame for the panel window in bottom-left screen coordinates.
    /// We always size the window to the *expanded* bounds plus shadow margin
    /// and let the SwiftUI content draw the collapsed strip inside it; a
    /// passthrough hit-test keeps the empty margins click-through.
    var windowFrame: CGRect {
        let f = screen.frame
        let w = expandedWidth + Self.shadowMargin * 2
        let h = expandedHeight + Self.shadowMargin
        let x = f.midX - w / 2
        // Anchor the top of the window to the top of the screen.
        let y = f.maxY - h
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

enum NotchGeometry {
    /// Fallback strip size when there is no hardware notch, so the app is still
    /// usable (and testable) on non-notch Macs and external displays.
    static let simulatedNotchSize = CGSize(width: 240, height: 32)

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let topInset = screen.safeAreaInsets.top

        if topInset > 0 {
            // Notch width = full width minus the two auxiliary areas beside it.
            let full = screen.frame.width
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let notchWidth = max(full - left - right, 180)
            return NotchMetrics(
                notchSize: CGSize(width: notchWidth, height: topInset),
                screen: screen,
                hasHardwareNotch: true
            )
        }

        return NotchMetrics(
            notchSize: simulatedNotchSize,
            screen: screen,
            hasHardwareNotch: false
        )
    }

    /// Screen the user is most likely looking at: the one with the notch, else
    /// the screen containing the mouse, else the main screen.
    static func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        let mouse = NSEvent.mouseLocation
        if let under = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return under
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }
}
