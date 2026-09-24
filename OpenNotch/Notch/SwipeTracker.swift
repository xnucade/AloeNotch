import CoreGraphics

/// Turns a stream of trackpad scroll deltas into at most one swipe per
/// gesture.
///
/// Pure on purpose (no AppKit), so it can be tested without a trackpad; the
/// view model feeds it from `PassthroughHostingView.scrollWheel`. Deltas are
/// in *finger* space — +x right, +y down — already corrected for natural
/// scrolling, so "swipe down" means the fingers moved down whatever the
/// user's scroll direction setting is.
///
/// The axis locks after a few points of travel, so a slightly diagonal swipe
/// can't fire both ways, and a gesture fires once: the rest of it — and the
/// momentum after it — is swallowed rather than firing again.
struct SwipeTracker {
    enum Swipe: Equatable { case up, down, left, right }
    enum Axis: Equatable { case horizontal, vertical }
    enum Phase: Equatable { case began, changed, ended, momentum }

    /// Travel before the axis is decided.
    static let lockDistance: CGFloat = 6
    /// Travel before a swipe counts. Long enough that resting two fingers on
    /// the trackpad while the pointer happens to be over the notch doesn't
    /// open it; short enough to be a flick, not a drag.
    static let threshold: CGFloat = 36

    private(set) var axis: Axis?
    private(set) var travel = CGSize.zero
    private(set) var fired = false
    private(set) var active = false

    /// Feed one event. Returns the swipe on the event that crosses the
    /// threshold, and nil for every other event.
    mutating func feed(_ phase: Phase, dx: CGFloat, dy: CGFloat) -> Swipe? {
        switch phase {
        case .began:
            self = SwipeTracker()
            active = true
        case .ended:
            active = false
            return nil
        case .momentum:
            return nil
        case .changed:
            guard active else { return nil }
        }
        travel.width += dx
        travel.height += dy
        if axis == nil, max(abs(travel.width), abs(travel.height)) >= Self.lockDistance {
            axis = abs(travel.width) > abs(travel.height) ? .horizontal : .vertical
        }
        guard !fired, let axis else { return nil }
        let distance = axis == .horizontal ? travel.width : travel.height
        guard abs(distance) >= Self.threshold else { return nil }
        fired = true
        return switch axis {
        case .horizontal: distance > 0 ? .right : .left
        case .vertical:   distance > 0 ? .down : .up
        }
    }

    /// How far the fingers have pulled down before the swipe fires — what
    /// the strip follows 1:1 (rubber-banded) so the gesture feels attached.
    var pull: CGFloat {
        guard active, !fired, axis != .horizontal else { return 0 }
        return max(0, travel.height)
    }

    /// Rubber band for the pull: follows the fingers at first, then resists,
    /// never passing `limit`.
    static func rubberBand(_ pull: CGFloat, limit: CGFloat) -> CGFloat {
        guard pull > 0 else { return 0 }
        return limit * (1 - 1 / (1 + pull / limit * 0.55))
    }
}
