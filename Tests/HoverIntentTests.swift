// Tests for telling a pointer settling on the notch from one passing through.

import CoreGraphics

func testHoverIntent() {
    var intent = HoverIntent()
    let window = HoverIntent.window

    expect(intent.isTravelling(at: .zero, time: 0) == nil, "the first sample only sets the anchor")
    expect(intent.isTravelling(at: CGPoint(x: 50, y: 0), time: window / 2) == nil,
           "a window shorter than the minimum is not measured")

    // Sweeping along the menu bar: 1000 pt/s.
    expect(intent.isTravelling(at: CGPoint(x: 20, y: 0), time: 0.02) == true,
           "a sweep across the strip is travelling")

    // Settling: 2 pt in 25 ms is 80 pt/s.
    expect(intent.isTravelling(at: CGPoint(x: 22, y: 0), time: 0.045) == false,
           "a pointer slowing onto the notch is arriving")

    // Vertical counts too: speed, not direction.
    expect(intent.isTravelling(at: CGPoint(x: 22, y: 30), time: 0.07) == true,
           "fast vertical movement is travelling")

    // A long pause followed by a move is measured over the pause: slow.
    expect(intent.isTravelling(at: CGPoint(x: 40, y: 30), time: 2) == false,
           "a nudge after a rest is not a sweep")

    intent.reset()
    expect(intent.isTravelling(at: CGPoint(x: 500, y: 0), time: 3) == nil,
           "after a reset nothing carries over from the last visit")
}
