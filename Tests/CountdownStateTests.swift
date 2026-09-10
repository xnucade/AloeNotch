// Tests for the countdown arithmetic.
//
// Every one of these takes an explicit `now` rather than reading the clock, so
// they are deterministic and can assert things a real timer would take twenty-
// five minutes to demonstrate.

import Foundation

func testCountdown() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    var s = CountdownState.started(300, at: t0)
    expect(s.isRunning, "a started countdown is running")
    expect(!s.isPaused && !s.isIdle, "running is not paused or idle")
    expect(s.remaining(at: t0) == 300, "nothing has elapsed at the start")
    expect(s.progress(at: t0) == 0, "the ring starts empty")

    expect(s.remaining(at: t0.addingTimeInterval(120)) == 180, "time elapses")
    expect(abs(s.progress(at: t0.addingTimeInterval(150)) - 0.5) < 0.0001,
           "halfway through is half a ring")

    // Deriving from a deadline is the whole point: a lid closed for an hour
    // must not leave the timer thinking an hour is still to run.
    expect(s.remaining(at: t0.addingTimeInterval(3600)) == 0, "remaining never goes negative")
    expect(s.progress(at: t0.addingTimeInterval(3600)) == 1, "the ring stops at full")
    expect(s.hasFinished(at: t0.addingTimeInterval(300)), "it has finished at the deadline")
    expect(!s.hasFinished(at: t0.addingTimeInterval(299)), "it has not finished a second early")

    // Pausing freezes the remainder rather than the deadline.
    let paused = s.paused(at: t0.addingTimeInterval(100))
    expect(paused.isPaused, "pausing pauses")
    expect(!paused.isRunning, "a paused countdown is not running")
    expect(paused.remaining(at: t0.addingTimeInterval(100)) == 200, "the remainder is kept")
    expect(paused.remaining(at: t0.addingTimeInterval(100_000)) == 200,
           "a paused countdown does not drain while the world moves on")
    expect(!paused.hasFinished(at: t0.addingTimeInterval(100_000)),
           "a paused countdown never fires")

    // Resuming picks up exactly where it stopped, whenever that happens to be.
    let resumed = paused.resumed(at: t0.addingTimeInterval(5_000))
    expect(resumed.isRunning, "resuming resumes")
    expect(resumed.remaining(at: t0.addingTimeInterval(5_000)) == 200,
           "resuming restores the remainder, not the original deadline")

    // Adding a minute mid-flight must move the ring as well as the clock,
    // otherwise progress jumps backwards the moment you press it.
    let extended = s.extended(by: 60, at: t0.addingTimeInterval(100))
    expect(extended.remaining(at: t0.addingTimeInterval(100)) == 260, "extending adds time")
    expect(extended.total == 360, "extending grows the total too")
    expect(extended.progress(at: t0.addingTimeInterval(100))
           < s.progress(at: t0.addingTimeInterval(100)),
           "extending moves the ring back, not forward")

    let extendedPause = paused.extended(by: 60, at: t0)
    expect(extendedPause.remaining(at: t0) == 260, "a paused countdown can be extended too")
    expect(CountdownState.idle.extended(by: 60, at: t0).isIdle,
           "extending nothing does nothing")

    expect(CountdownState.idle.isIdle, "idle is idle")
    expect(CountdownState.idle.remaining(at: t0) == 0, "idle has nothing remaining")
    expect(CountdownState.idle.progress(at: t0) == 0, "idle draws no ring")
    expect(CountdownState.started(0, at: t0).progress(at: t0) == 0,
           "a zero-length countdown does not divide by zero")

    s = CountdownState.idle
    expect(s.paused(at: t0).isIdle, "pausing nothing does nothing")
    expect(s.resumed(at: t0).isIdle, "resuming nothing does nothing")
}

func testCountdownFormatting() {
    // Rounded up, so a timer with 0.4s left never shows 0:00 while still going.
    expect(CountdownState.clock(0.4) == "0:01", "a fraction of a second still reads as one")
    expect(CountdownState.clock(0) == "0:00", "zero reads as zero")
    expect(CountdownState.clock(-5) == "0:00", "negative time is clamped")
    expect(CountdownState.clock(59) == "0:59", "under a minute")
    expect(CountdownState.clock(60) == "1:00", "exactly a minute")
    expect(CountdownState.clock(1500) == "25:00", "a pomodoro")
    expect(CountdownState.clock(3600) == "1:00:00", "an hour grows an hours field")
    expect(CountdownState.clock(3661) == "1:01:01", "hours, minutes and seconds")

    expect(CountdownState.label(60) == "1 min", "a minute preset")
    expect(CountdownState.label(1500) == "25 min", "a pomodoro preset")
    expect(CountdownState.label(3600) == "1 hr", "an hour preset")
    expect(CountdownState.label(7200) == "2 hr", "two hours")
    expect(CountdownState.label(5400) == "1:30", "an hour and a half")
}
