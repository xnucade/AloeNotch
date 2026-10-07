// Tests for resident arbitration in LiveActivityCenter.

import Foundation

private struct R: QueueableActivity {
    var kind: String
    var priority: Int
    var duration: TimeInterval = .infinity
    var payload = 0
}

func testResidentSlots() {
    typealias S = ResidentSlots<R>

    do {
        let s = S()
        expect(s.showing == nil, "no residents shows nothing")
    }

    // Higher priority wins whatever the order.
    do {
        var s = S()
        s.set(R(kind: "timer", priority: 30))
        s.set(R(kind: "calendar", priority: 20))
        expect(s.showing?.kind == "timer", "a lower-priority resident set later stays underneath")
        s.clear(kind: "timer")
        expect(s.showing?.kind == "calendar", "clearing the top resident reveals the one beneath")
        s.clear(kind: "calendar")
        expect(s.showing == nil, "clearing the last resident leaves nothing")
    }

    // Equal priority: most recently started wins.
    do {
        var s = S()
        s.set(R(kind: "timer", priority: 30))
        s.set(R(kind: "stopwatch", priority: 30))
        expect(s.showing?.kind == "stopwatch", "among equals the newest shows")
        s.set(R(kind: "timer", priority: 30, payload: 1))
        expect(s.showing?.kind == "stopwatch", "updating an older resident doesn't jump it ahead")
        s.clear(kind: "stopwatch")
        expect(s.showing?.kind == "timer" && s.showing?.payload == 1, "the update is kept underneath")
    }

    // Clearing something that isn't there is harmless.
    do {
        var s = S()
        s.set(R(kind: "timer", priority: 30))
        s.clear(kind: "missing")
        expect(s.showing?.kind == "timer", "clearing an unknown kind changes nothing")
        expect(s.contains(kind: "timer") && !s.contains(kind: "missing"), "contains reports membership")
    }

    // A cleared kind that comes back counts as new.
    do {
        var s = S()
        s.set(R(kind: "a", priority: 30))
        s.set(R(kind: "b", priority: 30))
        s.clear(kind: "a")
        s.set(R(kind: "a", priority: 30))
        expect(s.showing?.kind == "a", "a restarted resident is the newest again")
    }
}
