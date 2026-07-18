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
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]

        panel.contentView = host
        panel.setFrame(frame, display: true)

        self.panel = panel
        self.hostingView = host
    }

    /// The region that should receive mouse events, in the hosting view's
    /// (bottom-left origin) coordinate space.
    private func activeRect() -> CGRect {
        guard let host = hostingView else { return .zero }
        let bounds = host.bounds
        if viewModel.isExpanded {
            // The window carries a transparent shadow margin on the sides and
            // bottom; only the panel itself should take clicks.
            let w = metrics.expandedWidth
            let h = metrics.expandedHeight
            return CGRect(
                x: bounds.midX - w / 2,
                y: host.isFlipped ? bounds.minY : bounds.maxY - h,
                width: w,
                height: h
            )
        }
        // Collapsed: only the top-center notch strip (notch + wings).
        // NSHostingView is flipped (top-left origin), so "top" depends on the
        // flipped state.
        let w = metrics.collapsedSize.width
        let h = metrics.collapsedSize.height
        return CGRect(
            x: bounds.midX - w / 2,
            y: host.isFlipped ? bounds.minY : bounds.maxY - h,
            width: w,
            height: h
        )
    }

    /// Move the panel to the currently preferred screen and resize for its notch.
    func repositionOnActiveScreen() {
        let newMetrics = NotchGeometry.metrics(for: NotchGeometry.preferredScreen())
        self.metrics = newMetrics
        viewModel.metrics = newMetrics
        applyFrame(animate: false)
    }
}
