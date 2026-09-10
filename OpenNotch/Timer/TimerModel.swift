import AppKit
import Combine

/// A countdown that lives in the notch.
///
/// The one thing the notch is unarguably better at than a menu bar item: a
/// timer you can see without opening anything, and that takes over the collapsed
/// strip the way the Dynamic Island does. All the arithmetic is in
/// `CountdownState`; this owns the clock, the sound and the announcement.
final class TimerModel: ObservableObject {
    @Published private(set) var state: CountdownState = .idle
    /// Set when a timer runs out and cleared as soon as the user acknowledges
    /// it, so the panel can hold the "done" face until it is seen.
    @Published private(set) var finishedAt: Date?

    /// The last duration started, so the panel offers "again" rather than
    /// making the user re-pick. Persisted — it is a habit, not session state.
    @Published var lastDuration: TimeInterval {
        didSet { UserDefaults.standard.set(lastDuration, forKey: "timerLastDuration") }
    }

    /// What the preset row offers. Five, ten, twenty-five (a pomodoro) and an
    /// hour cover nearly everything anyone sets a kitchen timer for; one minute
    /// is there because it is the one people use to test that it works.
    static let presets: [TimeInterval] = [60, 5 * 60, 10 * 60, 25 * 60, 60 * 60]

    var isActive: Bool { !state.isIdle }

    private weak var center: LiveActivityCenter?
    private var ticker: Timer?

    init(center: LiveActivityCenter? = nil) {
        self.center = center
        let stored = UserDefaults.standard.double(forKey: "timerLastDuration")
        lastDuration = stored > 0 ? stored : 5 * 60
    }

    // MARK: Controls

    func start(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        lastDuration = duration
        finishedAt = nil
        state = .started(duration, at: Date())
        startTicking()
        publishActivity()
        Haptics.caught()
    }

    func pause() {
        state = state.paused(at: Date())
        publishActivity()
    }

    func resume() {
        state = state.resumed(at: Date())
        startTicking()
        publishActivity()
    }

    func extend(by delta: TimeInterval) {
        state = state.extended(by: delta, at: Date())
        publishActivity()
    }

    func cancel() {
        state = .idle
        finishedAt = nil
        stopTicking()
        center?.clearResident(kind: Self.kind)
        center?.dismiss(kind: Self.doneKind)
    }

    /// Dismiss the "done" face without starting anything new.
    func acknowledge() {
        finishedAt = nil
        center?.dismiss(kind: Self.doneKind)
    }

    // MARK: The clock

    private static let kind = "timer.running"
    private static let doneKind = "timer.done"

    /// Polls rather than scheduling a one-shot at the deadline. A one-shot that
    /// falls during sleep fires late or not at all, and `Timer` gives no
    /// guarantee across a lid close; re-reading the clock four times a second
    /// costs nothing and cannot drift.
    private func startTicking() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state.isRunning else { return stopTicking() }
        guard state.hasFinished(at: Date()) else { return }
        fire()
    }

    private func fire() {
        stopTicking()
        state = .idle
        finishedAt = Date()
        center?.clearResident(kind: Self.kind)
        center?.present(LiveActivity(
            kind: Self.doneKind,
            symbol: "bell.fill",
            tint: .orange,
            title: "Time's up",
            size: .regular,
            duration: 6,
            priority: LiveActivity.Priority.action
        ))
        // The system alert sound, not a bundled one: it already respects the
        // user's alert volume and their choice of sound, and a timer that is
        // louder than everything else they have configured is a bad neighbour.
        NSSound.beep()
    }

    /// Mirror the countdown into the collapsed strip.
    private func publishActivity() {
        guard let center else { return }
        guard !state.isIdle else { return center.clearResident(kind: Self.kind) }

        // An hour-plus countdown reads "1:00:00" — two more digits than the
        // regular wing was sized for, so it gets the wide one instead of being
        // clipped at the notch.
        let wide = CountdownState.clock(state.remaining(at: Date())).count > 5

        center.setResident(LiveActivity(
            kind: Self.kind,
            symbol: state.isPaused ? "pause.fill" : "timer",
            tint: .white,
            trailing: state.isPaused
                ? .text(CountdownState.clock(state.remaining(at: Date())))
                : .countdown(state.deadline ?? Date()),
            size: wide ? .wide : .regular,
            duration: .infinity,
            priority: LiveActivity.Priority.ambient
        ))
    }
}
