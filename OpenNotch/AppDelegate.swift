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
    private var whatsNewWindow: NSWindow?

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
        let settings = AppSettings.shared
        if !settings.hasSeenWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showWelcome()
            }
        } else if WhatsNew.shouldPresent(lastSeen: settings.lastSeenVersion,
                                         hasSeenWelcome: settings.hasSeenWelcome) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showWhatsNew()
            }
        } else {
            // Keep the marker current even when there is nothing to show, so a
            // release with no notes doesn't cause the *next* one to think the
            // user has fallen several versions behind.
            settings.lastSeenVersion = Self.currentVersion
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
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
            // Without this the window paints its own opaque backing and the
            // behind-window frost has nothing to show through.
            window.configureForGlass()
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
            window.configureForGlass()
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
        // A brand-new install has, by definition, just seen everything that is
        // new. Marking it here stops the what's-new sheet appearing on the very
        // next launch of a version the user has only just met.
        AppSettings.shared.lastSeenVersion = Self.currentVersion
        welcomeWindow?.close()
    }

    /// Release notes for a version the user hasn't run before.
    func showWhatsNew() {
        guard let entry = WhatsNew.current else { return }
        if whatsNewWindow == nil {
            let view = WhatsNewView(entry: entry) { [weak self] in
                self?.finishWhatsNew()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "What's New"
            window.styleMask = [.titled, .closable]
            window.configureForGlass()
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            whatsNewWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        whatsNewWindow?.makeKeyAndOrderFront(nil)
        whatsNewWindow?.orderFrontRegardless()
    }

    private func finishWhatsNew() {
        AppSettings.shared.lastSeenVersion = Self.currentVersion
        whatsNewWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Dismissing with the close button counts as seen — don't nag on relaunch.
        let closing = notification.object as? NSWindow
        if closing === welcomeWindow {
            AppSettings.shared.hasSeenWelcome = true
            AppSettings.shared.lastSeenVersion = Self.currentVersion
        }
        if closing === whatsNewWindow {
            AppSettings.shared.lastSeenVersion = Self.currentVersion
        }
        // Drop back to an accessory app once no windows of ours remain. Deferred
        // because the closing window is still visible at willClose time.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let anyVisible = [self.settingsWindow, self.welcomeWindow, self.whatsNewWindow]
                .contains { $0?.isVisible == true }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
