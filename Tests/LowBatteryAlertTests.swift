// Tests for the low-battery marks.

import Foundation

func testLowBatteryAlert() {
    typealias L = LowBatteryAlert
    expect(L.markCrossed(from: 0.21, to: 0.20, pluggedIn: false) == 20, "falling onto 20% is the first mark")
    expect(L.markCrossed(from: 0.20, to: 0.19, pluggedIn: false) == nil, "already under it: told once, not again")
    expect(L.markCrossed(from: 0.11, to: 0.10, pluggedIn: false) == 10, "10% is the second")
    expect(L.markCrossed(from: 0.25, to: 0.08, pluggedIn: false) == 10, "a jump past both reports the lower")
    expect(L.markCrossed(from: 0.21, to: 0.20, pluggedIn: true) == nil, "nothing on the charger")
    expect(L.markCrossed(from: 0.19, to: 0.21, pluggedIn: false) == nil, "rising is not a warning")
    expect(L.markCrossed(from: 0.204, to: 0.199, pluggedIn: false) == nil,
           "both round to 20%, so the percentage shown never crossed")
}
