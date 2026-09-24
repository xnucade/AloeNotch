import AppKit
import Quartz

/// What you can do with staged files besides dragging them out.
///
/// Both AirDrop and Quick Look open system windows of their own. The app is
/// an accessory with a non-activating panel, so it activates first — without
/// that, the AirDrop picker and the preview open *behind* whatever app was
/// frontmost, which looks like the button did nothing.
enum ShelfActions {
    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func quickLook(_ urls: [URL], startingAt index: Int = 0) {
        QuickLookSource.shared.show(urls, at: index)
    }
}

/// Feeds `QLPreviewPanel` directly rather than through the responder chain.
/// The chain route needs the panel's host to be key and to answer
/// `acceptsPreviewPanelControl`, and the notch panel stops being either the
/// moment the pointer leaves it for the preview.
private final class QuickLookSource: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookSource()
    private var urls: [URL] = []

    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        // A second click on what's already showing closes it, like Space in Finder.
        if panel.isVisible, self.urls == urls, panel.currentPreviewItemIndex == index {
            panel.orderOut(nil)
            return
        }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(index, urls.count - 1)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
