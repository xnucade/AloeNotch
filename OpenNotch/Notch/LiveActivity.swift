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
struct LiveActivity: Identifiable, Equatable {
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
    }

    let id = UUID()

    /// Dedupe key. A new activity with the same kind replaces the one showing
    /// and restarts its timer, which is what makes holding the volume key read
    /// as one readout tracking rather than a stack of them fighting.
    let kind: String

    let symbol: String
    var tint: Color = .white
    /// Optional label beside the symbol. Kept short — the wings are narrow.
    var title: String?
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
    /// Without a second slot a running timer would be evicted the first time
    /// the user touched a volume key and never return, because the center
    /// deliberately keeps no queue. The two are different in kind, not in
    /// priority: one announces that something happened, the other reports that
    /// something still is.
    @Published private(set) var resident: LiveActivity?

    /// What the notch should actually draw.
    var showing: LiveActivity? { current ?? resident }

    private var expiry: DispatchWorkItem?

    func present(_ activity: LiveActivity) {
        guard !activity.isResident else { return setResident(activity) }

        if let current, activity.priority < current.priority, activity.kind != current.kind {
            return
        }
        expiry?.cancel()
        current = activity

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.current?.id == activity.id else { return }
            self.current = nil
        }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + activity.duration, execute: work)
    }

    func setResident(_ activity: LiveActivity?) {
        resident = activity
    }

    func clearResident(kind: String) {
        if resident?.kind == kind { resident = nil }
    }

    /// Clear immediately — used when the thing being announced stops being true
    /// (the HUD pipeline shutting down, a device disconnecting mid-readout).
    func dismiss(kind: String? = nil) {
        if let kind, current?.kind != kind { return }
        expiry?.cancel()
        expiry = nil
        current = nil
    }
}
