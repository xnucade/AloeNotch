// Tests for when the next calendar event's countdown takes the strip.

import Foundation

func testNextEventWindow() {
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    typealias W = NextEventWindow

    expect(W.decide([], now: t0) == .init(showing: nil, recheck: nil), "no events: nothing, and nothing to wait for")

    let one = [(start: at(30), isAllDay: false)]
    expect(W.decide(one, now: t0) == .init(showing: nil, recheck: at(20)),
           "an event 30 minutes out waits for its window to open at -10")
    expect(W.decide(one, now: at(20)) == .init(showing: 0, recheck: at(30)),
           "the window opens exactly ten minutes before")
    expect(W.decide(one, now: at(29.9)) == .init(showing: 0, recheck: at(30)),
           "and stays open until the start")
    expect(W.decide(one, now: at(30)) == .init(showing: nil, recheck: nil),
           "an event that has started is no longer counted down to")

    let allDay = [(start: at(5), isAllDay: true)]
    expect(W.decide(allDay, now: t0).showing == nil, "all-day events never count down")

    // An ongoing meeting listed first must not hide the next one.
    let mixed = [(start: at(-15), isAllDay: false),
                 (start: at(8), isAllDay: true),
                 (start: at(9), isAllDay: false),
                 (start: at(4), isAllDay: false)]
    expect(W.decide(mixed, now: t0) == .init(showing: 3, recheck: at(4)),
           "the soonest future timed event wins regardless of order")
    expect(W.decide(mixed, now: at(4)) == .init(showing: 2, recheck: at(9)),
           "back to back: the next takes over as the first starts")
}
