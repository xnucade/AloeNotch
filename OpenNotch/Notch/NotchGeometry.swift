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

    /// Extra width on each side of the hardware notch, used to peek a small
    /// now-playing glyph out where it's actually visible.
    static let mediaWingWidth: CGFloat = 46

    /// Wings for a transient announcement, by how much room it asked for.
    /// `wide` fits a level bar or a device name; `regular` a percentage or a
    /// count; `compact` just a symbol.
    static func activityWingWidth(_ size: PanelState.ActivitySize) -> CGFloat {
        switch size {
        case .compact: 46
        case .regular: 64
        case .wide:    84
        }
    }

    /// The detached bubble of a split island, by the room its activity asked
    /// for. Same height as the strip so the two read as one material.
    static func bubbleWidth(_ size: PanelState.ActivitySize) -> CGFloat {
        switch size {
        case .compact: 36
        case .regular: 74
        case .wide:    94
        }
    }

    /// Air between the strip and the bubble at rest. Wide enough to read as
    /// two things even where the strip's shoulder flares into it at the
    /// bezel, close enough to read as siblings.
    static let bubbleGap: CGFloat = 9

    /// How far the bubble reaches past the strip's trailing edge, or 0. The
    /// hit-test rect grows by this on the right so hovering the bubble opens
    /// the panel like hovering the strip does.
    func bubbleExtent(for state: PanelState) -> CGFloat {
        guard let size = state.bubble else { return 0 }
        return Self.bubbleGap + Self.bubbleWidth(size)
    }

    /// On-screen size of the notch surface in a given state.
    ///
    /// Single source of truth: the SwiftUI frame and the window's hit-test rect
    /// both read this, so they cannot disagree about how big the panel is.
    /// Peek states grow into "wings" either side of the hardware notch so their
    /// content clears it; displays without a notch already show their whole
    /// simulated strip, so they don't grow.
    func size(for state: PanelState) -> CGSize {
        switch state {
        case .expanded:
            return CGSize(width: expandedWidth, height: expandedHeight)
        case .peek(let kind):
            guard hasHardwareNotch else { return notchSize }
            let wing: CGFloat = switch kind {
            case .media, .split:      Self.mediaWingWidth
            case .activity(let size): Self.activityWingWidth(size)
            }
            return CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
        case .collapsed:
            return notchSize
        }
    }

    // Expanded panel dimensions — wide and short, a horizontal three-column
    // layout (media · calendar · shelf).
    //
    // The floor keeps the panel wider than the collapsed strip no matter how
    // narrow the user sets it: a panel narrower than the notch it grows out of
    // would collapse *inward*, which looks broken rather than adjustable.
    var expandedWidth: CGFloat {
        max(collapsedSize.width + 40, CGFloat(AppSettings.shared.panelWidth))
    }
    var expandedHeight: CGFloat { AppSettings.shared.panelLayout.height }

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

    /// The screen the notch belongs on under the user's `DisplayChoice`.
    static func preferredScreen() -> NSScreen {
        let screens = NSScreen.screens
        let settings = AppSettings.shared
        let candidates = screens.map {
            DisplayChoice.Candidate(name: $0.localizedName, isBuiltIn: isBuiltIn($0))
        }
        if let i = DisplayChoice.pick(settings.displayChoice, pinnedName: settings.pinnedDisplay,
                                      from: candidates) {
            return screens[i]
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    /// The Mac's own panel, notched or not — a pre-notch MacBook's built-in
    /// display is still where the user expects it.
    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else {
            return screen.safeAreaInsets.top > 0
        }
        return CGDisplayIsBuiltin(id) != 0
    }
}
