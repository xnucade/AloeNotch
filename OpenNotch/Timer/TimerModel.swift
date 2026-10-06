import AppKit
import Combine
import SwiftUI

/// A countdown, a stopwatch or a focus session, living in the notch.
///
/// The one thing the notch is unarguably better at than a menu bar item: a
/// clock you can see without opening anything, and that takes over the
/// collapsed strip the way the Dynamic Island does. All the arithmetic is in
/// `CountdownState` and `StopwatchState`; this owns the clock, the sound and
/// the announcement.
///
/// One at a time. The mode picker hides while anything is running, so the
/// panel always has exactly one clock to show and one X that stops it.
final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case timer, stopwatch, focus
        var id: String { rawValue }

        var label: String {
            switch self {
            case .timer:     String(localized: "Timer")
            case .stopwatch: String(localized: "Stopwatch")
            case .focus:     String(localized: "Focus")
            }
        }

        var symbol: String {
            switch self {
            case .timer:     "timer"
            case .stopwatch: "stopwatch"
            case .focus:     "brain.head.profile"
            }
        }
    }

    /// The two halves of a focus session. Named `rest` because `break` is
    /// taken.
    enum FocusPhase { case focus, rest }

    /// Which face the idle panel offers. Persisted — someone who uses the
    /// stopwatch uses it every time.
    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "timerMode") }
    }

    @Published private(set) var state: CountdownState = .idle
    @Published private(set) var stopwatch: StopwatchState = .idle
    /// Set while a focus session's countdown is running, nil otherwise.
    @Published private(set) var focusPhase: FocusPhase?
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

    /// Twenty-five and five: the pomodoro as written. Fixed rather than
    /// configurable — the point of the technique is not deciding.
    static let focusLength: TimeInterval = 25 * 60
    static let breakLength: TimeInterval = 5 * 60

    var isActive: Bool { !state.isIdle || !stopwatch.isIdle }
    var isPaused: Bool { state.isPaused || stopwatch.isPaused }

    private weak var center: LiveActivityCenter?
    private var ticker: Timer?

    init(center: LiveActivityCenter? = nil) {
        self.center = center
        let stored = UserDefaults.standard.double(forKey: "timerLastDuration")
        lastDuration = stored > 0 ? stored : 5 * 60
        mode = UserDefaults.standard.string(forKey: "timerMode").flatMap(Mode.init) ?? .timer
    }

    // MARK: Controls

    func start(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        lastDuration = duration
        mode = .timer
        focusPhase = nil
        begin(duration)
        Haptics.caught()
    }

    func startStopwatch() {
        cancel()
        mode = .stopwatch
        stopwatch = .started(at: Date())
        publishActivity()
        Haptics.caught()
    }

    func startFocus() {
        mode = .focus
        focusPhase = .focus
        begin(Self.focusLength)
        Haptics.caught()
    }

    private func begin(_ duration: TimeInterval) {
        finishedAt = nil
        center?.dismiss(kind: Self.doneKind)
        stopwatch = .idle
        hourMark?.cancel()
        hourMark = nil
        state = .started(duration, at: Date())
        startTicking()
        publishActivity()
    }

    func pause() {
        if stopwatch.isRunning {
            stopwatch = stopwatch.paused(at: Date())
        } else {
            state = state.paused(at: Date())
        }
        publishActivity()
    }

    func resume() {
        if stopwatch.isPaused {
            stopwatch = stopwatch.resumed(at: Date())
        } else {
            state = state.resumed(at: Date())
            startTicking()
        }
        publishActivity()
    }

    func extend(by delta: TimeInterval) {
        state = state.extended(by: delta, at: Date())
        publishActivity()
    }

    func cancel() {
        state = .idle
        stopwatch = .idle
        focusPhase = nil
        finishedAt = nil
        stopTicking()
        hourMark?.cancel()
        hourMark = nil
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
        // The end of a focus stretch rolls straight into the break: having to
        // click something to start resting is one more decision the technique
        // exists to remove.
        if focusPhase == .focus {
            focusPhase = .rest
            state = .started(Self.breakLength, at: Date())
            publishActivity()
            announce(symbol: "cup.and.saucer.fill", tint: .green,
                     title: String(localized: "Break"))
            return
        }

        stopTicking()
        let wasRest = focusPhase == .rest
        focusPhase = nil
        state = .idle
        finishedAt = Date()
        center?.clearResident(kind: Self.kind)
        if wasRest {
            announce(symbol: "brain.head.profile", tint: .white,
                     title: String(localized: "Break's over"))
        } else {
            announce(symbol: "bell.fill", tint: .orange,
                     title: String(localized: "Time's up"))
        }
    }

    private func announce(symbol: String, tint: Color, title: String) {
        center?.present(LiveActivity(
            kind: Self.doneKind,
            symbol: symbol,
            tint: tint,
            title: title,
            size: .regular,
            duration: 6,
            priority: LiveActivity.Priority.action
        ))
        // The system alert sound, not a bundled one: it already respects the
        // user's alert volume and their choice of sound, and a timer that is
        // louder than everything else they have configured is a bad neighbour.
        NSSound.beep()
    }

    /// Re-publishes a running stopwatch when it passes the hour, so the
    /// strip widens for the extra digits. One shot, not a ticker.
    private var hourMark: DispatchWorkItem?

    /// Mirror the clock into the collapsed strip.
    private func publishActivity() {
        guard let center else { return }
        if !stopwatch.isIdle { return publishStopwatch(center) }
        guard !state.isIdle else { return center.clearResident(kind: Self.kind) }

        // An hour-plus countdown reads "1:00:00" — two more digits than the
        // regular wing was sized for, so it gets the wide one instead of being
        // clipped at the notch.
        let wide = CountdownState.clock(state.remaining(at: Date())).count > 5

        let symbol: String
        let tint: Color
        let name: String
        switch focusPhase {
        case .focus?: (symbol, tint, name) = ("brain.head.profile", .white, String(localized: "Focus"))
        case .rest?:  (symbol, tint, name) = ("cup.and.saucer.fill", .green, String(localized: "Break"))
        case nil:     (symbol, tint, name) = ("timer", .white, String(localized: "Timer"))
        }

        center.setResident(LiveActivity(
            kind: Self.kind,
            symbol: state.isPaused ? "pause.fill" : symbol,
            tint: tint,
            spokenName: state.isPaused ? String(localized: "\(name) paused") : name,
            trailing: state.isPaused
                ? .text(CountdownState.clock(state.remaining(at: Date())))
                : .countdown(state.deadline ?? Date()),
            size: wide ? .wide : .regular,
            duration: .infinity,
            priority: LiveActivity.Priority.ambient
        ))
    }

    private func publishStopwatch(_ center: LiveActivityCenter) {
        let now = Date()
        let elapsed = stopwatch.elapsed(at: now)
        hourMark?.cancel()
        hourMark = nil
        if let origin = stopwatch.origin, elapsed < 3600 {
            let work = DispatchWorkItem { [weak self] in self?.publishActivity() }
            hourMark = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + origin.addingTimeInterval(3600).timeIntervalSince(now),
                execute: work)
        }

        center.setResident(LiveActivity(
            kind: Self.kind,
            symbol: stopwatch.isPaused ? "pause.fill" : "stopwatch",
            tint: .white,
            spokenName: stopwatch.isPaused ? String(localized: "Stopwatch paused")
                                           : String(localized: "Stopwatch"),
            trailing: stopwatch.origin.map { .elapsed($0) } ?? .text(StopwatchState.clock(elapsed)),
            size: elapsed >= 3600 ? .wide : .regular,
            duration: .infinity,
            priority: LiveActivity.Priority.ambient
        ))
    }
}
