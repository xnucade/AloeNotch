import AppKit
import SwiftUI
import Combine

/// Owns the floating panel, positions it over the notch, and keeps the
/// passthrough hit-test region in sync with the collapsed/expanded state.
/// The hit-test rect is computed lazily per event via `activeRectProvider`,
/// so no explicit invalidation is needed when expansion changes.
final class NotchWindowController {
    private let viewModel: NotchViewModel
    private let settings = AppSettings.shared
    private var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<NotchRootView>?
    private var metrics: NotchMetrics
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.metrics = NotchGeometry.metrics(for: NotchGeometry.preferredScreen())
        viewModel.metrics = metrics

        // Nudge the panel live when the position offset changes in Settings.
        settings.$positionOffset
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrame(animate: false) }
            .store(in: &cancellables)

        // Panel width changes the *window* size, not just the content: the
        // window is sized to the expanded panel plus shadow margin, so without
        // this the panel would be clipped by a window that never grew.
        settings.$panelWidth
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrame(animate: false) }
            .store(in: &cancellables)

        // Layout changes both dimensions, so the window has to follow. Without
        // this, switching to the focused layout would draw a taller panel
        // inside a window still sized for the shorter one and clip it.
        // Applied live, so it can be switched on just before a share.
        settings.$displayChoice
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.repositionOnActiveScreen() }
            .store(in: &cancellables)

        settings.$hideFromCapture
            .dropFirst()
            .sink { [weak self] hide in self?.panel?.sharingType = hide ? .none : .readOnly }
            .store(in: &cancellables)

        settings.$panelLayout
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrame(animate: false) }
            .store(in: &cancellables)
    }

    /// Keyboard focus. The panel is non-activating, so taking key status
    /// leaves the app in front active; but while the panel is key, typing
    /// goes to it. So it takes focus only when opened with the shortcut, and
    /// gives it back whenever it finishes closing — including after a click
    /// on one of its buttons, which makes it key too.
    private func observeKeyboardFocus(of panel: NotchPanel) {
        panel.onCancel = { [weak viewModel] in viewModel?.cancelFromKeyboard() }

        viewModel.$hasKeyboardFocus
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak panel] _ in panel?.makeKey() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak viewModel] _ in viewModel?.keyboardFocusLost() }
            .store(in: &cancellables)

        viewModel.$panelState
            .map(\.isExpanded)
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                // Once the close has played out: ordering the window out and
                // back mid-close would blink the whole panel.
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.settle(Motion.Duration.collapse)) {
                    self?.releaseKeyFocus()
                }
            }
            .store(in: &cancellables)
    }

    /// Hand keyboard focus back to the app in front. A window can't resign
    /// key on request; leaving the screen is what returns focus, so the
    /// panel steps out and straight back in. By now it is only the strip,
    /// black on the black of the notch.
    private func releaseKeyFocus() {
        guard let panel, panel.isKeyWindow, !viewModel.panelState.isExpanded else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// The window frame with the user's horizontal offset applied.
    private func positionedFrame() -> CGRect {
        var frame = metrics.windowFrame
        frame.origin.x += CGFloat(settings.positionOffset)
        return frame
    }

    private func applyFrame(animate: Bool) {
        panel?.setFrame(positionedFrame(), display: true, animate: animate)
    }

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFrontRegardless()
    }

    private func buildPanel() {
        let frame = positionedFrame()
        let panel = NotchPanel(contentRect: frame)

        let root = NotchRootView(viewModel: viewModel)
        let host = PassthroughHostingView(rootView: root)
        host.activeRectProvider = { [weak self] in self?.activeRect() ?? .zero }
        host.onScroll = { [weak viewModel] event in viewModel?.handleScroll(event) ?? false }
        host.registerForDraggedTypes([.fileURL])
        host.onDragMoved = { [weak self] point in
            guard let self else { return }
            guard let point else { return self.viewModel.dragMoved(nil) }
            // −1 at the surface's left edge, 1 at its right.
            let rect = self.activeRect()
            let bias = rect.width > 0 ? (point.x - rect.midX) / (rect.width / 2) : 0
            self.viewModel.dragMoved(min(1, max(-1, bias)))
        }
        host.onDropped = { [weak self] accepted in
            self?.viewModel.dropLanded(accepted)
            // Pointer tracking is suspended for the length of a drag, so the
            // hover exit may never come. Check where the pointer is once the
            // drop has settled rather than trusting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let self, let panel = self.panel, let host = panel.contentView else { return }
                let local = host.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                if !self.activeRect().contains(local) { self.viewModel.hoverChanged(false) }
            }
        }
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        // The controller owns the window frame. By default the hosting view
        // pushes the SwiftUI content's min/max size onto the window, which
        // gives AppKit a second opinion about how wide the panel may be.
        host.sizingOptions = []

        panel.contentView = host
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        panel.setFrame(frame, display: true)

        self.panel = panel
        self.hostingView = host

        observeKeyboardFocus(of: panel)

        // The window server can move or shrink the panel on its own while
        // displays reconfigure — sleep, clamshell, a monitor coming and going —
        // and the screen-parameters notification doesn't always follow. A
        // squeezed window recentres its content off the hardware notch, so one
        // side of the strip overhangs the cutout. Whenever the frame drifts,
        // put it back.
        NotificationCenter.default
            .publisher(for: NSWindow.didResizeNotification, object: panel)
            .merge(with: NotificationCenter.default
                .publisher(for: NSWindow.didMoveNotification, object: panel))
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restoreFrameIfDrifted() }
            .store(in: &cancellables)

        // After wake the screen list settles late; re-read it rather than
        // trusting the metrics from before sleep.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .delay(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.repositionOnActiveScreen() }
            .store(in: &cancellables)
    }

    private func restoreFrameIfDrifted() {
        guard let panel else { return }
        let target = positionedFrame()
        if panel.frame.integral != target.integral {
            panel.setFrame(target, display: true)
        }
    }

    /// The region that should receive mouse events, in the hosting view's
    /// (bottom-left origin) coordinate space.
    ///
    /// The window carries a transparent margin on the sides and bottom so the
    /// glow can bloom; only the surface itself should take clicks. The size
    /// comes from `hitTestState` rather than `panelState` — see the note on
    /// that property for why the two differ while collapsing.
    private func activeRect() -> CGRect {
        guard let host = hostingView else { return .zero }
        let bounds = host.bounds
        let size = metrics.size(for: viewModel.hitTestState)
        // A split island's bubble sits off the strip's right edge.
        let bubble = metrics.bubbleExtent(for: viewModel.hitTestState)
        // NSHostingView is flipped (top-left origin), so "top" depends on the
        // flipped state.
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: host.isFlipped ? bounds.minY : bounds.maxY - size.height,
            width: size.width + bubble,
            height: size.height
        )
    }

    /// "Move Here": pin the notch to the display under the pointer.
    func moveToPointerScreen() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            settings.pinnedDisplay = screen.localizedName
            settings.displayChoice = .chosen
        }
        repositionOnActiveScreen()
    }

    /// Move the panel to the currently preferred screen and resize for its notch.
    func repositionOnActiveScreen() {
        let newMetrics = NotchGeometry.metrics(for: NotchGeometry.preferredScreen())
        self.metrics = newMetrics
        viewModel.metrics = newMetrics
        applyFrame(animate: false)
    }
}
