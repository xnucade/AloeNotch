// Tests for telling keyboard-backlight changes someone made apart from the
// ambient light sensor's.

import Foundation

func testBacklightChangeFilter() {
    // Recorded with auto-brightness on and nobody touching anything:
    // (seconds, level). None of it should put the readout up.
    let sensor: [(TimeInterval, Float)] = [
        (10.05, 0.2743365), (10.25, 0.2871022), (10.45, 0.2998678), (10.65, 0.2807193),
        (11.05, 0.2679537), (11.26, 0.2488052), (11.46, 0.2615709), (12.06, 0.2424224),
        (12.67, 0.2551880), (12.87, 0.2679537), (13.07, 0.2551880), (13.27, 0.2424224),
        (13.88, 0.2615709), (15.69, 0.2424224),
    ]
    var filter = BacklightChangeFilter()
    filter.reset(to: 0.24880522)
    let shown = sensor.filter { filter.shouldShow($0.1, at: $0.0, autoBrightness: true) }
    expect(shown.isEmpty, "the ambient sensor's own steps are not announced")

    // A key press with auto-brightness on.
    filter.reset(to: 0.25)
    expect(filter.shouldShow(0.3125, at: 20, autoBrightness: true), "a one-sixteenth key step is announced")
    expect(filter.shouldShow(0.33, at: 20.3, autoBrightness: true), "small steps right behind a jump still count")
    expect(!filter.shouldShow(0.345, at: 20.7, autoBrightness: true), "the follow-up window isn't extended by small steps")

    // The sensor stepping right after a jump can't chain the window forever.
    filter.reset(to: 0.5)
    _ = filter.shouldShow(0.6, at: 30, autoBrightness: true)
    var t: TimeInterval = 30
    var late = 0
    for i in 1...10 {
        t += 0.2
        if filter.shouldShow(0.6 + Float(i) * 0.0128, at: t, autoBrightness: true), t - 30 > 0.6 { late += 1 }
    }
    expect(late == 0, "sensor steps after the window closes are ignored")

    // Auto-brightness off: nothing else moves the level, so any change counts.
    filter.reset(to: 0.4)
    expect(filter.shouldShow(0.413, at: 40, autoBrightness: false), "with auto-brightness off, a small change is announced")
    expect(!filter.shouldShow(0.415, at: 40.1, autoBrightness: false), "a sub-noise wobble is not")

    // No seed: the first reading can't be measured against anything.
    filter.reset()
    expect(!filter.shouldShow(0.3, at: 50, autoBrightness: true), "an unseeded first reading isn't announced under auto-brightness")
    filter.reset()
    expect(filter.shouldShow(0.3, at: 50, autoBrightness: false), "but is when auto-brightness is off")
}
