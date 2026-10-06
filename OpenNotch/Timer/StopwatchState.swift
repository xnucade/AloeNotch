import Foundation

/// The arithmetic of a stopwatch, kept apart from any clock for the same
/// reason `CountdownState` is: what a pause does to the total is the part that
/// can be got wrong, and it is pure.
///
/// Stored as an *origin* — the instant the stopwatch would have started had it
/// never been paused — rather than as a running total that something has to
/// keep adding to. Elapsed time is then just `now - origin`, which survives a
/// closed lid and needs nobody ticking, and the strip can hand the origin
/// straight to SwiftUI to count up from.
struct StopwatchState: Equatable {
    /// Set while running.
    var origin: Date?
    /// What had elapsed at the moment of pausing. Set only while paused.
    var pausedElapsed: TimeInterval?

    var isRunning: Bool { origin != nil }
    var isPaused: Bool { pausedElapsed != nil }
    var isIdle: Bool { origin == nil && pausedElapsed == nil }

    func elapsed(at now: Date) -> TimeInterval {
        if let pausedElapsed { return pausedElapsed }
        guard let origin else { return 0 }
        return max(0, now.timeIntervalSince(origin))
    }

    static func started(at now: Date) -> StopwatchState {
        StopwatchState(origin: now, pausedElapsed: nil)
    }

    func paused(at now: Date) -> StopwatchState {
        guard isRunning else { return self }
        return StopwatchState(origin: nil, pausedElapsed: elapsed(at: now))
    }

    func resumed(at now: Date) -> StopwatchState {
        guard let pausedElapsed else { return self }
        return StopwatchState(origin: now.addingTimeInterval(-pausedElapsed), pausedElapsed: nil)
    }

    static let idle = StopwatchState()

    /// `m:ss` under an hour, `h:mm:ss` above it. Rounded *down*, the opposite
    /// of a countdown: a stopwatch that reads 0:01 a moment after starting has
    /// claimed a second that hasn't happened.
    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(max(0, seconds).rounded(.down))
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
