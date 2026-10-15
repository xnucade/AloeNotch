import AppKit

/// A borderless, non-activating floating panel that sits above the menu bar and
/// hugs the notch. It joins every Space and stays put during full-screen apps.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .init(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Do not become key/main automatically; the panel should never steal focus.
    }

    /// Whether the panel may take keyboard focus right now. The controller
    /// allows it only for the active display's panel while it is open, or
    /// while the shortcut has given it focus. A closed strip never takes
    /// focus, so typing never lands in it and there is nothing to give back.
    var allowsKey: () -> Bool = { true }

    override var canBecomeKey: Bool { allowsKey() }

    override func becomeKey() {
        super.becomeKey()
        NotchTrace.log.notice("panel became key")
    }

    override func resignKey() {
        super.resignKey()
        NotchTrace.log.notice("panel resigned key")
    }
    override var canBecomeMain: Bool { false }

    /// Esc. Arrives through `cancelOperation` when the hosting view
    /// interprets the key, or as a bare key-down when nothing inside does.
    var onCancel: (() -> Void)?

    /// Any other key nothing inside handled. Returns true when the key
    /// wasn't meant for the panel at all, which skips the beep.
    var onStrayKey: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if onStrayKey?() == true { return }
        super.keyDown(with: event)
    }

    /// The frame is computed to the point from the notch's geometry; AppKit's
    /// idea of a sensible window position (below the menu bar, inside the
    /// visible frame) would knock it off the cutout.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
