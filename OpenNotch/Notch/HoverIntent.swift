import CoreGraphics
import Foundation

/// Tells a pointer settling on the notch from one sweeping past it.
///
/// The notch sits in the menu bar, so the pointer crosses it all the time on
/// the way from the menus to the status items. With only a fixed delay, a
/// crossing that happened to spend longer than the delay inside the strip
/// opened the panel. Speed is what separates the two: a pointer arriving at
/// a target slows to almost nothing (that is how aimed movement ends), and a
/// pointer passing through doesn't.
///
/// Fed from hover events rather than sampled on a timer, so it costs nothing
/// while the pointer is elsewhere or still.
struct HoverIntent {
    /// Above this the pointer is travelling, not arriving. Points per second.
    static let travelSpeed: CGFloat = 300
    /// The shortest span measured over. Consecutive events can be a
    /// millisecond apart, and a speed over that span is mostly noise.
    static let window: TimeInterval = 0.02

    private var anchor: (point: CGPoint, time: TimeInterval)?

    mutating func reset() { anchor = nil }

    /// Feed one pointer position. True when it is moving fast enough to be
    /// passing through, false when it is slow enough to be arriving, nil
    /// while a measuring window is still filling.
    mutating func isTravelling(at point: CGPoint, time: TimeInterval) -> Bool? {
        guard let anchor else {
            self.anchor = (point, time)
            return nil
        }
        let elapsed = time - anchor.time
        guard elapsed >= Self.window else { return nil }
        self.anchor = (point, time)
        let distance = hypot(point.x - anchor.point.x, point.y - anchor.point.y)
        return distance / CGFloat(elapsed) > Self.travelSpeed
    }
}
