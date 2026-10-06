import SwiftUI
import Combine

/// One transient thing worth announcing in the notch.
///
/// Before this existed there were two hardcoded announcements — the
/// volume/brightness HUD and the charging acknowledgement — each with its own
/// published property on the view model, its own dismissal timer, its own case
/// in `PanelState`, its own branch in the view and its own wing width. Adding a
/// third would have meant repeating all five. Everything transient now goes
/// through one type and one queue, so a new announcement is a `LiveActivity`
/// value and a detector, not a new special case.
struct LiveActivity: Identifiable, Equatable, QueueableActivity {
    /// What sits on the right-hand wing, opposite the symbol.
    enum Trailing: Equatable {
        case none
        /// A 0...1 bar — volume, brightness, charge.
        case level(Double)
        /// A short string: a percentage, a device name, a file count.
        case text(String)
        /// Counts down to a date, rendered live by SwiftUI rather than by
        /// anyone re-presenting the activity every second — a running timer
        /// would otherwise restart its arrival beat sixty times a minute.
        case countdown(Date)
        /// A song: the title, scrolling if it has to, over the artist.
        case track(title: String, artist: String)
    }

    let id = UUID()

    /// Dedupe key. A new activity with the same kind replaces the one showing
    /// and restarts its timer, which is what makes holding the volume key read
    /// as one readout tracking rather than a stack of them fighting.
    let kind: String

    let symbol: String
    /// Lead with the now-playing cover instead of the symbol, read live so a
    /// cover that arrives after the title still lands. The symbol stands in
    /// until it does.
    var showsArtwork = false
    var tint: Color = .white
    /// Optional label beside the symbol. Kept short — the wings are narrow.
    var title: String?
    /// What VoiceOver calls it when there's no title, or the title alone
    /// wouldn't say what happened ("Brightness", "Backup ejected").
    var spokenName: String?
    var trailing: Trailing = .none
    var size: PanelState.ActivitySize = .regular

    /// How long it stays up. `.infinity` marks a *resident* activity — one that
    /// is true until something stops being true (a timer running, a screen
    /// being shared) rather than one that announces and goes.
    var duration: TimeInterval = 2.0

    var isResident: Bool { duration.isInfinite }

    /// Higher wins. A volume readout you are actively driving must not be
    /// buried by a Bluetooth device connecting in the background.
    var priority: Int = 0

    /// One sentence for VoiceOver: the name, then whatever the wing shows.
    var accessibilityText: String {
        let name = spokenName ?? title ?? ""
        let value: String? = switch trailing {
        case .none: nil
        case .level(let level): "\(Int((min(1, max(0, level)) * 100).rounded())) percent"
        case .text(let text): text
        case .countdown(let deadline): "\(CountdownState.clock(deadline.timeIntervalSinceNow)) remaining"
        case .track: nil
        }
        return [name, value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func == (a: LiveActivity, b: LiveActivity) -> Bool {
        a.kind == b.kind && a.symbol == b.symbol && a.title == b.title
            && a.trailing == b.trailing && a.size == b.size && a.priority == b.priority
    }
}

// MARK: - Priorities

extension LiveActivity {
    /// Named so the ordering is legible in one place rather than inferred from
    /// magic numbers scattered across detectors.
    enum Priority {
        /// Something the user is driving right now with a key they are holding.
        static let direct = 100
        /// A direct physical action: plugging in, ejecting, taking a shot.
        static let action = 60
        /// Something that happened on its own: a device connected, a download
        /// finished.
        static let ambient = 30
    }
}

// MARK: - Center

/// Holds the activity currently showing and decides what replaces it.
///
/// Deliberately not a queue. Transient system announcements go stale fast — a
/// "download finished" that waits behind two other activities and appears four
/// seconds late is worse than one that never appeared, because the user has to
/// work out what it is referring to. Higher priority preempts, equal priority
/// replaces, lower priority is dropped.
///
/// Main-thread only, by convention rather than by `@MainActor`: it is owned by
/// `NotchViewModel`, which is not actor-isolated (nor is any other observable
/// object here), and annotating just this one would force every call site
/// through an `await` for no benefit. Detectors that observe background
/// notifications must hop to main before presenting.
final class LiveActivityCenter: ObservableObject {
    /// The transient announcement showing right now, if any.
    @Published private(set) var current: LiveActivity?

    /// A standing condition — a timer counting down, say. Transients display
    /// over it and it comes back when they expire.
    ///
    /// Kept out of the announcement queue: a running timer is not news that
    /// waits its turn and expires, it is a standing fact that transients play
    /// over and give back to. The two are different in kind, not in
    /// priority: one announces that something happened, the other reports that
    /// something still is.
    @Published private(set) var resident: LiveActivity?

    /// What the notch should actually draw.
    var showing: LiveActivity? { current ?? resident }

    /// A level readout was pushed past its stop — volume up at 100%, down at
    /// 0. `count` only exists to change on every push, so a held key replays
    /// the stretch; `direction` is +1 at the top, -1 at the bottom.
    struct LimitPush: Equatable { var count = 0; var direction = 1 }
    @Published private(set) var limitPush = LimitPush()

    func pushAgainstLimit(_ direction: Int) {
        limitPush = LimitPush(count: limitPush.count + 1, direction: direction)
    }

    /// Decides what shows and for how long — see `ActivityQueue` for the
    /// rules. This class only owns the clock and publishes the result.
    private var queue = ActivityQueue<LiveActivity>(directPriority: LiveActivity.Priority.direct)
    private var expiry: DispatchWorkItem?

    func present(_ activity: LiveActivity) {
        guard !activity.isResident else { return setResident(activity) }
        queue.present(activity, now: Date())
        sync()
    }

    /// True while the panel is expanded and covering the strip. Announcements
    /// stop counting down until it closes, so none is spent unseen.
    func setPaused(_ paused: Bool) {
        queue.setPaused(paused, now: Date())
        sync()
    }

    /// Publish what the queue decided and arm the one timer for its next
    /// change.
    private func sync() {
        let next = queue.current
        if next?.id != current?.id {
            // Volume and brightness are left to the system, which already
            // speaks them; announcing each step on top would talk over it.
            if let next, next.kind != current?.kind, next.priority < LiveActivity.Priority.direct {
                Self.announce(next)
            }
            current = next
        }

        expiry?.cancel()
        expiry = nil
        guard let deadline = queue.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.advance(now: Date())
            self.sync()
        }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
    }

    /// The panel is a borderless window VoiceOver users rarely have focus
    /// in, so anything that appears there is invisible to them unless it's
    /// spoken. Only while VoiceOver is actually running.
    private static func announce(_ activity: LiveActivity) {
        let text = activity.accessibilityText
        guard !text.isEmpty, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    func setResident(_ activity: LiveActivity?) {
        if let activity, resident?.kind != activity.kind { Self.announce(activity) }
        resident = activity
    }

    func clearResident(kind: String) {
        if resident?.kind == kind { resident = nil }
    }

    /// Clear immediately — used when the thing being announced stops being true
    /// (the HUD pipeline shutting down, a device disconnecting mid-readout).
    func dismiss(kind: String? = nil) {
        queue.dismiss(kind: kind, now: Date())
        sync()
    }
}
