import Foundation

/// When a falling battery is worth a word in the notch.
///
/// Once at 20% and once at 10%, on the way down and on battery power only.
/// Crossing a mark is the event, not being under it, so a Mac that sits at
/// 15% is told once rather than on every reading.
enum LowBatteryAlert {
    static let marks = [20, 10]

    /// The mark crossed between two readings, as a percentage, or nil.
    static func markCrossed(from old: Double, to new: Double, pluggedIn: Bool) -> Int? {
        guard !pluggedIn else { return nil }
        let before = percent(old), now = percent(new)
        return marks.filter { before > $0 && now <= $0 }.min()
    }

    static func percent(_ level: Double) -> Int { Int((level * 100).rounded()) }
}
