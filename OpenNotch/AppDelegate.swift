import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchController: NotchWindowController?
    private var viewModel: NotchViewModel?
    private var screenObserver: AnyCancellable?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Turn a plain SIGTERM (kill, logout) into a graceful quit so
        // applicationWillTerminate runs and the media adapter child is
        // shut down instead of orphaned.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source

        let vm = NotchViewModel()
        let controller = NotchWindowController(viewModel: vm)
        controller.show()

        self.viewModel = vm
        self.notchController = controller

        // Re-place the panel when the screen arrangement changes
        // (display connected/disconnected, resolution change, etc.).
        screenObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak controller] _ in
                controller?.repositionOnActiveScreen()
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.tearDown()
    }
}
