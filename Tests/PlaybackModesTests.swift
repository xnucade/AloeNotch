// Tests for reading and stepping the shuffle and repeat modes.

import Foundation

func testPlaybackModes() {
    expect(ShuffleMode(payload: nil) == nil, "no key: the player isn't saying, so no button")
    expect(ShuffleMode(payload: NSNumber(value: 0)) == nil, "unknown is treated as not reported")
    expect(ShuffleMode(payload: NSNumber(value: 3)) == .tracks, "a reported mode reads through")
    expect(ShuffleMode(payload: "3") == nil, "a value of the wrong type is ignored")
    expect(RepeatMode(payload: NSNumber(value: 9)) == nil, "an out-of-range mode is ignored")

    expect(ShuffleMode.off.toggled == .tracks, "shuffle turns on as tracks")
    expect(ShuffleMode.albums.toggled == .off, "album shuffle counts as on and turns off")

    var mode = RepeatMode.off
    var seen: [RepeatMode] = []
    for _ in 0..<3 { mode = mode.next; seen.append(mode) }
    expect(seen == [.all, .one, .off], "repeat steps off, all, one, off, as Music does")
}
