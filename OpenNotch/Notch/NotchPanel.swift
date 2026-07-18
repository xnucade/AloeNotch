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

    override var canBecomeKey: Bool { true }   // needed so buttons/drag targets work
    override var canBecomeMain: Bool { false }
}
