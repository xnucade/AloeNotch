import Foundation

/// What the queue needs to know about an announcement. `LiveActivity`
/// conforms; the tests use a plain struct, so the rules can be checked
/// without SwiftUI.
protocol QueueableActivity {
    var kind: String { get }
    var priority: Int { get }
    var duration: TimeInterval { get }
}

/// Decides which transient announcement is on screen, and for how long.
///
/// Before this, the center kept one slot and no queue: a lower-priority
/// announcement arriving during a higher one was discarded, everything kept
/// expiring while the panel was open and covering it, and two equal ones
/// arriving together could flash the first for a single frame. The rules:
///
/// - **Higher priority preempts.** What it interrupts goes back to the front
///   of the line with the time it had left.
/// - **Equal priority takes turns.** The newcomer waits until the one showing
///   has been up for `minimumDwell`, then replaces it — the newest news wins,
///   but nothing flashes.
/// - **Lower priority waits** for the one showing to finish.
/// - **The same kind replaces in place**, showing or waiting: a held volume
///   key is one readout tracking, not a stack.
/// - **At most `capacity` wait.** Past that the least important, then oldest,
///   is dropped.
/// - **Paused while the panel is expanded**, so an announcement that arrives
///   under an open panel is still seen when it closes — unless it's older
///   than `staleAfter` by then, at which point it isn't news. `direct`
///   announcements (a key being held) are about right now and never pause.
///
/// Pure and clock-injected: every call takes `now`, and `nextDeadline` says
/// when to call `advance` again. The center owns the one timer.
struct ActivityQueue<Item: QueueableActivity> {
    static var minimumDwell: TimeInterval { 0.6 }
    static var staleAfter: TimeInterval { 5 }
    static var capacity: Int { 3 }

    /// Priority at or above which an announcement ignores pausing.
    let directPriority: Int

    init(directPriority: Int) {
        self.directPriority = directPriority
    }

    struct Showing {
        var item: Item
        /// When it went on screen, for the dwell rule.
        var shownAt: Date
        /// When it arrived or was last re-queued, for the staleness rule.
        var since: Date
        /// Time left on screen. Counts down only while running.
        var remaining: TimeInterval
        /// When `remaining` last started counting; nil while paused.
        var runningSince: Date?

        func left(at now: Date) -> TimeInterval {
            guard let runningSince else { return remaining }
            return remaining - now.timeIntervalSince(runningSince)
        }
    }

    struct Waiting {
        var item: Item
        var since: Date
        /// How long it gets once shown; less than its full duration when it
        /// was interrupted partway.
        var remaining: TimeInterval
    }

    private(set) var showing: Showing?
    private(set) var waiting: [Waiting] = []
    private(set) var isPaused = false

    var current: Item? { showing?.item }

    // MARK: Inputs

    mutating func present(_ item: Item, now: Date) {
        advance(now: now)

        guard var shown = showing else {
            show(Waiting(item: item, since: now, remaining: item.duration), now: now)
            return
        }

        if shown.item.kind == item.kind {
            // Same kind: new payload, timer restarts. The dwell clock does
            // not, or a held key would keep everything behind it waiting.
            shown.item = item
            shown.since = now
            shown.remaining = item.duration
            shown.runningSince = runs(item) ? now : nil
            showing = shown
            return
        }

        if item.priority > shown.item.priority {
            let left = shown.left(at: now)
            if left > 0 {
                enqueue(Waiting(item: shown.item, since: now, remaining: left), front: true)
            }
            show(Waiting(item: item, since: now, remaining: item.duration), now: now)
            return
        }

        enqueue(Waiting(item: item, since: now, remaining: item.duration), front: false)
        // The one showing may already be past its dwell, in which case an
        // equal newcomer takes over now rather than on the next tick.
        advance(now: now)
    }

    /// Take something off screen and out of the line — it stopped being true.
    /// With no kind, whatever is showing goes.
    mutating func dismiss(kind: String?, now: Date) {
        if let kind {
            waiting.removeAll { $0.item.kind == kind }
            guard showing?.item.kind == kind else { return }
        }
        showing = nil
        promote(now: now)
    }

    /// Stop or restart the clocks — true while the panel is expanded.
    mutating func setPaused(_ paused: Bool, now: Date) {
        guard paused != isPaused else { return }
        advance(now: now)
        isPaused = paused
        guard var shown = showing else { return promote(now: now) }

        if paused {
            // A held key keeps counting; everything else stops.
            guard !isDirect(shown.item), shown.runningSince != nil else { return }
            shown.remaining = shown.left(at: now)
            shown.runningSince = nil
            showing = shown
        } else {
            if now.timeIntervalSince(shown.since) > Self.staleAfter, !isDirect(shown.item) {
                showing = nil
                return promote(now: now)
            }
            if shown.runningSince == nil {
                shown.runningSince = now
                // Back on screen after the panel covered it: it owes the
                // viewer a full dwell before anything replaces it.
                shown.shownAt = now
                showing = shown
            }
        }
    }

    /// Move time forward: expire what is done and bring on what is next.
    mutating func advance(now: Date) {
        while let shown = showing, let end = endTime(of: shown), end <= now {
            showing = nil
            // From when it actually ended, so a backlog caught up in one
            // call plays out as it would have in real time.
            promote(now: end)
        }
    }

    /// When `advance` next has something to do, or nil if nothing will
    /// happen until another input arrives.
    var nextDeadline: Date? {
        guard let showing else { return nil }
        return endTime(of: showing)
    }

    // MARK: Internals

    private func isDirect(_ item: Item) -> Bool { item.priority >= directPriority }

    /// Whether this item's clock runs in the current pause state.
    private func runs(_ item: Item) -> Bool { !isPaused || isDirect(item) }

    private func endTime(of shown: Showing) -> Date? {
        guard let runningSince = shown.runningSince else { return nil }
        var end = runningSince.addingTimeInterval(shown.remaining)
        // An equal-priority newcomer cuts the one showing short — after the
        // dwell, never before.
        if let next = waiting.first, next.item.priority >= shown.item.priority {
            end = min(end, max(shown.shownAt.addingTimeInterval(Self.minimumDwell), runningSince))
        }
        return end
    }

    private mutating func show(_ entry: Waiting, now: Date) {
        // A backlog is replayed from when each one really ended, but nothing
        // goes on screen before it arrived.
        let start = max(now, entry.since)
        showing = Showing(item: entry.item, shownAt: start, since: entry.since,
                          remaining: entry.remaining,
                          runningSince: runs(entry.item) ? start : nil)
    }

    private mutating func promote(now: Date) {
        waiting.removeAll { now.timeIntervalSince($0.since) > Self.staleAfter }
        // Under an open panel only a held key may come on; the rest wait
        // for it to close.
        guard let index = isPaused ? waiting.firstIndex(where: { isDirect($0.item) })
                                   : waiting.indices.first else { return }
        show(waiting.remove(at: index), now: now)
    }

    private mutating func enqueue(_ entry: Waiting, front: Bool) {
        if let i = waiting.firstIndex(where: { $0.item.kind == entry.item.kind }) {
            // Keep its place in line; take the newer payload and clock.
            waiting[i] = entry
            return
        }
        // Highest priority first; arrival order within a priority, except an
        // interrupted announcement, which resumes ahead of its peers.
        let index = waiting.firstIndex {
            front ? $0.item.priority <= entry.item.priority
                  : $0.item.priority < entry.item.priority
        } ?? waiting.endIndex
        waiting.insert(entry, at: index)
        if waiting.count > Self.capacity { waiting.removeLast() }
    }
}
