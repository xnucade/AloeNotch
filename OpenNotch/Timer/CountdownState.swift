import Foundation

/// The arithmetic of a countdown, with no clock, no timer and no app attached.
///
/// Separated from `TimerModel` for the same reason `PanelState` is separated
/// from the view model: everything that can be got wrong here — what remains
/// after a pause, how far along the ring should be, how a duration reads as
/// text — is pure, and pure code can be tested in a second from a shell.
struct CountdownState: Equatable {
    /// When it will fire. Nil while paused or idle.
    var deadline: Date?
    /// What was left at the moment of pausing. Nil unless paused.
    var pausedRemaining: TimeInterval?
    /// What the user asked for, kept so the ring knows how far along it is and
    /// so "start again" doesn't need the user to pick the duration twice.
    var total: TimeInterval = 0

    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isIdle: Bool { deadline == nil && pausedRemaining == nil }

    /// Seconds left, never negative.
    ///
    /// Derived from a *deadline* rather than counted down tick by tick, so a
    /// closed lid, a missed timer fire or a busy main thread cannot make the
    /// timer drift. The clock is the source of truth; we only read it.
    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// 0 at the start, 1 when it fires. Drives the ring.
    func progress(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / total))
    }

    func hasFinished(at now: Date) -> Bool {
        guard let deadline, pausedRemaining == nil else { return false }
        return now >= deadline
    }

    // MARK: Transitions

    static func started(_ duration: TimeInterval, at now: Date) -> CountdownState {
        CountdownState(deadline: now.addingTimeInterval(duration),
                       pausedRemaining: nil,
                       total: duration)
    }

    func paused(at now: Date) -> CountdownState {
        guard isRunning else { return self }
        var s = self
        s.pausedRemaining = remaining(at: now)
        s.deadline = nil
        return s
    }

    func resumed(at now: Date) -> CountdownState {
        guard let left = pausedRemaining else { return self }
        var s = self
        s.deadline = now.addingTimeInterval(left)
        s.pausedRemaining = nil
        return s
    }

    /// Add time to a timer already in flight — the "+1 min" everyone reaches
    /// for when the pasta isn't done. Extends the total too, so the ring keeps
    /// telling the truth instead of jumping backwards.
    func extended(by delta: TimeInterval, at now: Date) -> CountdownState {
        guard !isIdle else { return self }
        var s = self
        s.total += delta
        if let deadline { s.deadline = deadline.addingTimeInterval(delta) }
        if let left = pausedRemaining { s.pausedRemaining = left + delta }
        return s
    }

    static let idle = CountdownState()
}

// MARK: - Formatting

extension CountdownState {
    /// `m:ss` under an hour, `h:mm:ss` above it. Rounded *up*, so a timer with
    /// 0.4s left reads "0:01" rather than showing 0:00 for almost a second
    /// before it fires.
    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(max(0, seconds).rounded(.up))
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// How a preset reads on its button: "1 min", "25 min", "1 hr".
    static func label(_ seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded())
        if t % 3600 == 0 { return "\(t / 3600) hr" }
        if t >= 3600 { return String(format: "%d:%02d", t / 3600, (t % 3600) / 60) }
        return "\(t / 60) min"
    }
}
