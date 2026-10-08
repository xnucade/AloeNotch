import AppKit
import SwiftUI
import Combine

/// Owns the floating panels, positions each over its display's notch, and
/// keeps the passthrough hit-test regions in sync with the panel state.
/// The hit-test rect is computed lazily per event via `activeRectProvider`,
/// so no explicit invalidation is needed when expansion changes.
///
/// One panel normally, on the display `DisplayChoice` picks. With "Every
/// display" on, one per connected display, all drawing from the one view
/// model; the panel the pointer last reached is the active one (see
/// `DisplayPresence`).
final class NotchWindowController {
    /// One display's window.
    private final class ScreenPanel {
        var displayID: CGDirectDisplayID
        var screen: NSScreen
        let presence: DisplayPresence
        let panel: NotchPanel
        let host: PassthroughHostingView<NotchRootView>
        var cancellables = Set<AnyCancellable>()

        var metrics: NotchMetrics { presence.metrics }

        init(displayID: CGDirectDisplayID, screen: NSScreen, presence: DisplayPresence,
             panel: NotchPanel, host: PassthroughHostingView<NotchRootView>) {
            self.displayID = displayID
            self.screen = screen
            self.presence = presence
            self.panel = panel
            self.host = host
        }
    }

    private let viewModel: NotchViewModel
    private let settings = AppSettings.shared
    private var panels: [ScreenPanel] = []
    private weak var active: ScreenPanel?
    private var isShown = false
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        viewModel.metrics = NotchGeometry.metrics(for: NotchGeometry.preferredScreen())

        // Nudge the panel live when the position offset changes in Settings.
        settings.$positionOffset
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrames() }
            .store(in: &cancellables)

        // Panel width changes the *window* size, not just the content: the
        // window is sized to the expanded panel plus shadow margin, so without
        // this the panel would be clipped by a window that never grew.
        settings.$panelWidth
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrames() }
            .store(in: &cancellables)

        // Which display is preferred moves the open panel there.
        settings.$displayChoice
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildPanels(resetActive: true) }
            .store(in: &cancellables)

        settings.$showOnAllDisplays
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildPanels(resetActive: true) }
            .store(in: &cancellables)

        settings.$hideFromCapture
            .dropFirst()
            .sink { [weak self] hide in
                self?.panels.forEach { $0.panel.sharingType = hide ? .none : .readOnly }
            }
            .store(in: &cancellables)

        // Layout changes both dimensions, so the window has to follow. Without
        // this, switching to the focused layout would draw a taller panel
        // inside a window still sized for the shorter one and clip it.
        // Applied live, so it can be switched on just before a share.
        settings.$panelLayout
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrames() }
            .store(in: &cancellables)

        // After wake the screen list settles late; re-read it rather than
        // trusting the metrics from before sleep.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .delay(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.repositionOnActiveScreen() }
            .store(in: &cancellables)

        // A full-screen app on another display hides that display's strip.
        // The window list lags the Space change a beat.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .delay(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMirrorVisibility() }
            .store(in: &cancellables)

        // The shortcut opens on the display the pointer is on.
        viewModel.onKeyboardOpen = { [weak self] in self?.claimPointerScreen() }

        observeKeyboardFocus()
    }

    /// Keyboard focus. The panel is non-activating, so taking key status
    /// leaves the app in front active; but while the panel is key, typing
    /// goes to it. So it takes focus only when opened with the shortcut, and
    /// gives it back whenever it finishes closing — including after a click
    /// on one of its buttons, which makes it key too.
    private func observeKeyboardFocus() {
        viewModel.$hasKeyboardFocus
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.active?.panel.makeKey() }
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
        guard !viewModel.panelState.isExpanded,
              let key = panels.first(where: { $0.panel.isKeyWindow }) else { return }
        key.panel.orderOut(nil)
        key.panel.orderFrontRegardless()
    }

    /// The window frame, with the user's horizontal offset applied on a
    /// display without a notch. On a real notch the offset is ignored: the
    /// strip has to sit exactly on the cutout, and any nudge breaks that.
    private func positionedFrame(for p: ScreenPanel) -> CGRect {
        var frame = p.metrics.windowFrame
        if !p.metrics.hasHardwareNotch {
            frame.origin.x += CGFloat(settings.positionOffset)
        }
        return frame
    }

    private func applyFrames() {
        for p in panels {
            p.panel.setFrame(positionedFrame(for: p), display: true, animate: false)
        }
    }

    func show() {
        if panels.isEmpty { rebuildPanels(resetActive: true) }
        isShown = true
        panels.forEach { $0.panel.orderFrontRegardless() }
    }

    /// Match the panels to the displays: the preferred one, or every one.
    ///
    /// Panels are kept by display where they can be and otherwise moved
    /// before any is made or dropped, so with one display (or "Every
    /// display" off) this moves the one panel exactly as it always has.
    private func rebuildPanels(resetActive: Bool) {
        let preferred = NotchGeometry.preferredScreen()
        let screens = settings.showOnAllDisplays ? NSScreen.screens : [preferred]
        let wanted = screens.compactMap { s in s.displayID.map { (id: $0, screen: s) } }

        var spare = panels.filter { p in !wanted.contains { $0.id == p.displayID } }
        var next: [ScreenPanel] = []
        for (id, screen) in wanted {
            let metrics = NotchGeometry.metrics(for: screen)
            if let p = panels.first(where: { $0.displayID == id }) ?? (spare.isEmpty ? nil : spare.removeFirst()) {
                p.displayID = id
                p.screen = screen
                p.presence.metrics = metrics
                next.append(p)
            } else {
                next.append(makePanel(displayID: id, screen: screen, metrics: metrics))
            }
        }
        // What's left over belongs to a display that's gone, or to "Every
        // display" being switched off.
        for p in spare {
            p.cancellables.removeAll()
            p.panel.orderOut(nil)
        }
        panels = next

        let survivor = resetActive ? nil : next.first { $0 === active }
        let fallback = next.first { $0.displayID == preferred.displayID } ?? next.first
        if let target = survivor ?? fallback {
            activate(target, force: true)
        }
        applyFrames()
        if isShown { panels.forEach { $0.panel.orderFrontRegardless() } }
        refreshMirrorVisibility()
    }

    private func makePanel(displayID: CGDirectDisplayID, screen: NSScreen,
                           metrics: NotchMetrics) -> ScreenPanel {
        let presence = DisplayPresence(metrics: metrics, isActive: false)
        let panel = NotchPanel(contentRect: metrics.windowFrame)
        let host = PassthroughHostingView(rootView: NotchRootView(viewModel: viewModel, presence: presence))
        let p = ScreenPanel(displayID: displayID, screen: screen, presence: presence,
                            panel: panel, host: host)
        presence.claim = { [weak self, weak p] in
            guard let self, let p else { return }
            self.activate(p)
        }

        host.activeRectProvider = { [weak self, weak p] in
            guard let self, let p else { return .zero }
            return self.activeRect(for: p)
        }
        host.onScroll = { [weak self, weak p] event in
            guard let self, let p, p === self.active else { return false }
            return self.viewModel.handleScroll(event)
        }
        host.registerForDraggedTypes([.fileURL])
        host.onDragMoved = { [weak self, weak p] point in
            guard let self, let p else { return }
            guard let point else {
                if p === self.active { self.viewModel.dragMoved(nil) }
                return
            }
            self.activate(p)
            // −1 at the surface's left edge, 1 at its right.
            let rect = self.activeRect(for: p)
            let bias = rect.width > 0 ? (point.x - rect.midX) / (rect.width / 2) : 0
            self.viewModel.dragMoved(min(1, max(-1, bias)))
        }
        host.onDropped = { [weak self, weak p] accepted in
            guard let self, let p, p === self.active else { return }
            self.viewModel.dropLanded(accepted)
            // Pointer tracking is suspended for the length of a drag, so the
            // hover exit may never come. Check where the pointer is once the
            // drop has settled rather than trusting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak p] in
                guard let self, let p, p === self.active, let host = p.panel.contentView else { return }
                let local = host.convert(p.panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                if !self.activeRect(for: p).contains(local) { self.viewModel.hoverChanged(false) }
            }
        }
        host.frame = CGRect(origin: .zero, size: metrics.windowFrame.size)
        host.autoresizingMask = [.width, .height]
        // The controller owns the window frame. By default the hosting view
        // pushes the SwiftUI content's min/max size onto the window, which
        // gives AppKit a second opinion about how wide the panel may be.
        host.sizingOptions = []

        panel.contentView = host
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        panel.onCancel = { [weak viewModel] in viewModel?.cancelFromKeyboard() }

        NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self, weak p] _ in
                guard let self, let p, p === self.active else { return }
                self.viewModel.keyboardFocusLost()
            }
            .store(in: &p.cancellables)

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
            .sink { [weak self, weak p] _ in
                guard let self, let p else { return }
                self.restoreFrameIfDrifted(p)
            }
            .store(in: &p.cancellables)

        return p
    }

    /// Make `p` the panel that follows hover and opens.
    private func activate(_ p: ScreenPanel, force: Bool = false) {
        guard force || p !== active else { return }
        if p !== active {
            active?.presence.isActive = false
            p.presence.isActive = true
            active = p
        }
        viewModel.metrics = p.metrics
        if panels.count > 1 {
            viewModel.activeDisplayChanged()
            refreshMirrorVisibility()
        }
    }

    /// For the shortcut: the panel on the pointer's display, if it has one.
    private func claimPointerScreen() {
        let mouse = NSEvent.mouseLocation
        if let p = panels.first(where: { $0.screen.frame.contains(mouse) }) {
            activate(p)
        }
    }

    /// Strips on displays other than the active one step aside for a
    /// full-screen app there, as the active one does through the view model.
    private func refreshMirrorVisibility() {
        guard panels.count > 1 || panels.first?.panel.alphaValue != 1 else { return }
        for p in panels {
            let hidden = !p.presence.isActive && settings.hideInFullScreen
                && FullScreenDetector.isFullScreen(on: p.screen)
            p.panel.alphaValue = hidden ? 0 : 1
            p.panel.ignoresMouseEvents = hidden
        }
    }

    private func restoreFrameIfDrifted(_ p: ScreenPanel) {
        let target = positionedFrame(for: p)
        if p.panel.frame.integral != target.integral {
            p.panel.setFrame(target, display: true)
        }
    }

    /// The region that should receive mouse events, in the hosting view's
    /// (bottom-left origin) coordinate space.
    ///
    /// The window carries a transparent margin on the sides and bottom so the
    /// glow can bloom; only the surface itself should take clicks. The size
    /// comes from `hitTestState` rather than `panelState` — see the note on
    /// that property for why the two differ while collapsing. A panel that
    /// isn't active takes the pointer over its resting strip, so reaching it
    /// can make it active.
    private func activeRect(for p: ScreenPanel) -> CGRect {
        let host = p.host
        let bounds = host.bounds
        let state = p.presence.isActive ? viewModel.hitTestState : viewModel.restingState
        let size = p.metrics.size(for: state)
        // A split island's bubble sits off the strip's right edge.
        let bubble = p.metrics.bubbleExtent(for: state)
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

    /// Re-read the displays: move the panel to the preferred screen (or
    /// match one to each) and resize for its notch.
    func repositionOnActiveScreen() {
        rebuildPanels(resetActive: false)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
