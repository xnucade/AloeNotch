import Foundation

/// Decides which keyboard-backlight changes are worth announcing.
///
/// With automatic keyboard brightness on (the macOS default), the ambient
/// light sensor moves the backlight level itself: small steps, a few times a
/// second, whenever the light in the room shifts. Measured on a MacBook Pro,
/// 1.3–2.6% per step every 0.2 s. Announcing those put the readout up over
/// and over with nobody touching anything.
///
/// A change someone makes is a bigger jump: a key press is a sixteenth
/// (6.25%), and the Control Center slider moves faster than the sensor
/// ramps. So while auto-brightness is on, only a jump of at least
/// `userStep` counts, plus the small steps right behind it (the tail of a
/// slider drag). With it off, nothing else moves the level, so every change
/// counts.
struct BacklightChangeFilter {
    /// Twice the largest step the sensor was seen taking.
    static let userStep: Float = 0.05
    /// How long after a jump smaller steps still count. Anchored to the jump,
    /// never extended by the steps themselves, so the sensor can't chain it.
    static let followUp: TimeInterval = 0.6
    /// Below this, the level hasn't really changed.
    static let noise: Float = 0.005

    private var previous: Float?
    private var lastJump: TimeInterval = -.infinity

    /// Forget history, optionally seeding the current level so the first
    /// change has something to be measured against.
    mutating func reset(to level: Float? = nil) {
        previous = level
        lastJump = -.infinity
    }

    mutating func shouldShow(_ level: Float, at time: TimeInterval, autoBrightness: Bool) -> Bool {
        defer { previous = level }
        guard let previous else { return !autoBrightness }
        let delta = abs(level - previous)
        guard delta > Self.noise else { return false }
        guard autoBrightness else { return true }
        if delta >= Self.userStep {
            lastJump = time
            return true
        }
        return time - lastJump <= Self.followUp
    }
}
