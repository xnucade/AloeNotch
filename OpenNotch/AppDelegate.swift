import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var notchController: NotchWindowController?
    private var viewModel: NotchViewModel?
    private var screenObserver: AnyCancellable?
    private var sigtermSource: DispatchSourceSignal?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

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
        vm.onOpenSettings = { [weak self] in self?.showSettings() }
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

        // First launch: the app is invisible until hovered, so introduce it.
        if !AppSettings.shared.hasSeenWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showWelcome()
            }
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
                onReposition: { [weak self] in self?.notchController?.repositionOnActiveScreen() },
                onShowWelcome: { [weak self] in self?.showWelcome() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "AloeNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // Accessory apps can't bring a window forward over another app; become a
        // regular app while Settings is open, then revert on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    /// Show (or focus) the first-run welcome. Also reachable from Settings.
    func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(onDone: { [weak self] in self?.finishWelcome() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to AloeNotch"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            welcomeWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
        welcomeWindow?.orderFrontRegardless()
    }

    private func finishWelcome() {
        AppSettings.shared.hasSeenWelcome = true
        welcomeWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Dismissing with the close button counts as seen — don't nag on relaunch.
        if (notification.object as? NSWindow) === welcomeWindow {
            AppSettings.shared.hasSeenWelcome = true
        }
        // Drop back to an accessory app once no windows of ours remain. Deferred
        // because the closing window is still visible at willClose time.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let anyVisible = [self.settingsWindow, self.welcomeWindow]
                .contains { $0?.isVisible == true }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
