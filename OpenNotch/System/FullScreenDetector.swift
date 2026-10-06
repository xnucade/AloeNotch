import AppKit
import CoreGraphics

/// Whether another app is full screen on a display.
///
/// There's no public "is it full screen" for other apps' windows, and asking
/// through Accessibility would stretch that permission past the HUD it's
/// granted for. The window list answers without any permission: a full-screen
/// window covers the whole display and the menu bar is gone, because macOS
/// hides it in full screen. A zoomed window covers the same area but has the
/// menu bar above it.
///
/// Asked when it matters (the pointer reaching the notch, a Space changing),
/// never on a timer. A call takes about 0.2 ms, except the first in a process,
/// which pays ~11 ms of setup; `warmUp` spends that off the main thread at
/// launch so the first hover doesn't.
enum FullScreenDetector {
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        }
    }

    static func isFullScreen(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // Window bounds are in global display space with a top-left origin.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        let display = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        let me = ProcessInfo.processInfo.processIdentifier
        var covered = false

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict)
            else { continue }
            let onDisplay = bounds.maxX > display.minX + 1 && bounds.minX < display.maxX - 1
                && bounds.maxY > display.minY + 1 && bounds.minY < display.maxY - 1
            guard onDisplay else { continue }

            // The menu bar is showing on this display: not full screen.
            if layer == menuBarLayer { return false }

            if layer == 0, (info[kCGWindowOwnerPID as String] as? pid_t) != me,
               bounds.minX <= display.minX + 1, bounds.maxX >= display.maxX - 1,
               bounds.maxY >= display.maxY - 1,
               // Full-screen windows on a notched display start below the
               // notch unless the app asks otherwise.
               bounds.minY <= display.minY + screen.safeAreaInsets.top + 1 {
                covered = true
            }
        }
        return covered
    }
}
