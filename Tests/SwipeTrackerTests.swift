// Tests for the trackpad swipe classifier behind the notch gestures.

func testSwipeTracker() {
    func run(_ steps: [(SwipeTracker.Phase, Double, Double)]) -> [SwipeTracker.Swipe] {
        var t = SwipeTracker()
        return steps.compactMap { t.feed($0.0, dx: $0.1, dy: $0.2) }
    }
    let down = [(SwipeTracker.Phase.began, 0.0, 2.0)] + Array(repeating: (.changed, 0.0, 8.0), count: 8)

    expect(run(down) == [.down], "a steady pull down fires once")
    expect(run(down.map { ($0.0, $0.1, -$0.2) }) == [.up], "and up")
    expect(run(down.map { ($0.0, $0.2, 0) }) == [.right], "and right")
    expect(run(down.map { ($0.0, -$0.2, 0) }) == [.left], "and left")

    expect(run([(.began, 0, 2), (.changed, 0, 10), (.changed, 0, 10)]).isEmpty,
           "short of the threshold is nothing — two resting fingers must not open the panel")
    expect(run(down + Array(repeating: (.changed, 0.0, 8.0), count: 20)) == [.down],
           "the rest of a long gesture doesn't fire again")
    expect(run(down + [(.ended, 0, 0)] + Array(repeating: (.momentum, 0.0, 30.0), count: 5)) == [.down],
           "momentum after the fingers lift is swallowed")
    expect(run(Array(repeating: (.changed, 0.0, 30.0), count: 5)).isEmpty,
           "no gesture without a beginning")

    // Axis lock: mostly-horizontal first, then drifting vertical, stays horizontal.
    let diagonal: [(SwipeTracker.Phase, Double, Double)] =
        [(.began, 0, 0), (.changed, 7, 2)] + Array(repeating: (.changed, 4.0, 9.0), count: 10)
    expect(!run(diagonal).contains(.down), "the axis locks — a drift can't fire the other way")

    // A second gesture starts clean.
    var t = SwipeTracker()
    for s in down { _ = t.feed(s.0, dx: s.1, dy: s.2) }
    _ = t.feed(.ended, dx: 0, dy: 0)
    var second: [SwipeTracker.Swipe] = []
    for s in down { if let f = t.feed(s.0, dx: s.1, dy: -s.2) { second.append(f) } }
    expect(second == [.up], "each gesture fires on its own")

    // The pull the strip follows.
    var p = SwipeTracker()
    _ = p.feed(.began, dx: 0, dy: 4)
    _ = p.feed(.changed, dx: 0, dy: 10)
    expect(p.pull == 14, "pull tracks downward travel 1:1")
    _ = p.feed(.changed, dx: 0, dy: 30)
    expect(p.pull == 0, "and lets go once the swipe fires")
    expect(SwipeTracker.rubberBand(0, limit: 10) == 0, "no pull, no stretch")
    expect(SwipeTracker.rubberBand(1000, limit: 10) < 10, "the rubber band never passes its limit")
    expect(SwipeTracker.rubberBand(10, limit: 10) < SwipeTracker.rubberBand(20, limit: 10),
           "but keeps giving")
}
