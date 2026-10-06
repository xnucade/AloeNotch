// Tests for the announcement queue in front of LiveActivityCenter.

import Foundation

private struct A: QueueableActivity {
    var kind: String
    var priority: Int
    var duration: TimeInterval = 2
    var payload = 0
}

private let direct = 100, action = 60, ambient = 30
private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

func testActivityQueue() {
    typealias Q = ActivityQueue<A>

    // Nothing showing: it shows, and expires on time.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "a", priority: ambient), now: at(0))
        expect(q.current?.kind == "a", "an announcement shows at once on an empty queue")
        expect(q.nextDeadline == at(2), "it is due to end after its duration")
        q.advance(now: at(1.9))
        expect(q.current?.kind == "a", "still up just before its time")
        q.advance(now: at(2))
        expect(q.current == nil, "gone at its time")
    }

    // S1: a lower priority arriving during a higher one waits instead of
    // being thrown away.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct), now: at(0))
        q.present(A(kind: "device", priority: ambient), now: at(0.5))
        expect(q.current?.kind == "hud", "the higher one keeps the strip")
        q.advance(now: at(2))
        expect(q.current?.kind == "device", "the lower one plays when it ends")
        expect(q.nextDeadline == at(4), "with its full duration")
    }

    // Higher priority preempts, and the interrupted one resumes with what it
    // had left.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "device", priority: ambient), now: at(0))
        q.present(A(kind: "hud", priority: direct), now: at(0.5))
        expect(q.current?.kind == "hud", "a held key preempts")
        q.advance(now: at(2.5))
        expect(q.current?.kind == "device", "the interrupted one comes back")
        expect(q.nextDeadline == at(4), "with the 1.5 s it had left")
    }

    // S3: equal priority takes turns, never flashing the first for a frame.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "a", priority: ambient), now: at(0))
        q.present(A(kind: "b", priority: ambient), now: at(0.05))
        expect(q.current?.kind == "a", "the first is not replaced on arrival")
        expect(q.nextDeadline == at(Q.minimumDwell), "it yields after the dwell")
        q.advance(now: at(Q.minimumDwell))
        expect(q.current?.kind == "b", "then the newer one shows")
    }
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "a", priority: ambient), now: at(0))
        q.present(A(kind: "b", priority: ambient), now: at(1))
        expect(q.current?.kind == "b", "already past the dwell, the newcomer takes over at once")
        expect(q.nextDeadline == at(3), "with its full duration")
    }

    // Lower priority waits for the full duration, not just the dwell.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "plug", priority: action), now: at(0))
        q.present(A(kind: "device", priority: ambient), now: at(0.1))
        expect(q.nextDeadline == at(2), "a lower newcomer does not cut the dwell")
    }

    // Same kind replaces in place: a held key is one readout.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct, payload: 1), now: at(0))
        q.present(A(kind: "hud", priority: direct, payload: 2), now: at(1.5))
        expect(q.current?.payload == 2, "the newer payload shows")
        expect(q.waiting.isEmpty, "nothing stacks")
        expect(q.nextDeadline == at(3.5), "and the timer restarts")
    }
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct), now: at(0))
        q.present(A(kind: "x", priority: ambient, payload: 1), now: at(0.1))
        q.present(A(kind: "y", priority: ambient), now: at(0.2))
        q.present(A(kind: "x", priority: ambient, payload: 2), now: at(0.3))
        expect(q.waiting.map(\.item.kind) == ["x", "y"], "a waiting kind keeps its place")
        expect(q.waiting.first?.item.payload == 2, "with the newer payload")
    }

    // Order: priority, then arrival. Capacity drops the least important.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct, duration: 10), now: at(0))
        q.present(A(kind: "amb1", priority: ambient), now: at(0.1))
        q.present(A(kind: "act", priority: action), now: at(0.2))
        q.present(A(kind: "amb2", priority: ambient), now: at(0.3))
        expect(q.waiting.map(\.item.kind) == ["act", "amb1", "amb2"], "priority first, then arrival")
        q.present(A(kind: "act2", priority: action), now: at(0.4))
        expect(q.waiting.map(\.item.kind) == ["act", "act2", "amb1"],
               "past capacity the newest of the lowest priority goes")
    }

    // Stale entries are dropped rather than played late.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct, duration: 8), now: at(0))
        q.present(A(kind: "device", priority: ambient), now: at(1))
        q.advance(now: at(8))
        expect(q.current == nil, "seven seconds late is not news")
    }

    // S2: paused while expanded, so it is seen when the panel closes.
    do {
        var q = Q(directPriority: direct)
        q.setPaused(true, now: at(0))
        q.present(A(kind: "plug", priority: action), now: at(1))
        expect(q.nextDeadline == nil, "no clock runs under an open panel")
        q.advance(now: at(3))
        expect(q.current?.kind == "plug", "still there at the end of its duration")
        q.setPaused(false, now: at(3.5))
        expect(q.nextDeadline == at(5.5), "and plays in full once the panel closes")
    }
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "plug", priority: action), now: at(0))
        q.setPaused(true, now: at(0.5))
        q.setPaused(false, now: at(2))
        expect(q.nextDeadline == at(3.5), "a pause mid-showing keeps the time it had left")
    }
    do {
        var q = Q(directPriority: direct)
        q.setPaused(true, now: at(0))
        q.present(A(kind: "plug", priority: action), now: at(1))
        q.setPaused(false, now: at(7))
        expect(q.current == nil, "a panel open for too long makes it stale")
    }
    do {
        var q = Q(directPriority: direct)
        q.setPaused(true, now: at(0))
        q.present(A(kind: "hud", priority: direct), now: at(1))
        expect(q.nextDeadline == at(3), "a held key never pauses")
        q.advance(now: at(3))
        q.setPaused(false, now: at(10))
        expect(q.current == nil, "so it is not replayed after the panel closes")
    }
    do {
        var q = Q(directPriority: direct)
        q.setPaused(true, now: at(0))
        q.present(A(kind: "plug", priority: action), now: at(0.5))
        q.present(A(kind: "hud", priority: direct), now: at(1))
        q.advance(now: at(3))
        expect(q.current == nil, "after a held key under an open panel, the rest still wait")
        q.setPaused(false, now: at(3.2))
        expect(q.current?.kind == "plug", "and come on when it closes")
    }

    // Dismiss: off screen and out of the line.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "hud", priority: direct), now: at(0))
        q.present(A(kind: "device", priority: ambient), now: at(0.1))
        q.dismiss(kind: "hud", now: at(0.5))
        expect(q.current?.kind == "device", "dismissing the one showing brings on the next")
        q.present(A(kind: "x", priority: ambient - 1), now: at(0.6))
        q.dismiss(kind: "x", now: at(0.7))
        expect(q.waiting.isEmpty, "dismissing a waiting kind removes it")
        q.dismiss(kind: "nope", now: at(0.8))
        expect(q.current?.kind == "device", "dismissing another kind leaves it be")
    }

    // A backlog caught up in one call plays out as it would have live.
    do {
        var q = Q(directPriority: direct)
        q.present(A(kind: "a", priority: action), now: at(0))
        q.present(A(kind: "b", priority: ambient), now: at(0.1))
        q.present(A(kind: "c", priority: ambient - 1), now: at(0.2))
        q.advance(now: at(4.5))
        expect(q.current?.kind == "c", "two expiries in one advance")
        expect(q.nextDeadline == at(6), "timed from when each really ended")
    }
}
