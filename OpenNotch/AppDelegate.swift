import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchController: NotchWindowController?
    private var viewModel: NotchViewModel?
    private var screenObserver: AnyCancellable?
    private var sigtermSource: DispatchSourceSignal?
    private var settingsWindow: NSWindow?

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

    /// Open (or focus) the preferences window. As an accessory app we must
    /// activate ourselves for the window to come forward and take input.
    func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onReposition: { [weak self] in self?.notchController?.repositionOnActiveScreen() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "AloeNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
