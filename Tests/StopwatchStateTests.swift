// Tests for the stopwatch arithmetic behind the timer module.

import Foundation

func testStopwatch() {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    let idle = StopwatchState.idle
    expect(idle.isIdle && !idle.isRunning && !idle.isPaused, "a fresh stopwatch is idle")
    expect(idle.elapsed(at: at(50)) == 0, "an idle stopwatch reads zero")
    expect(idle.paused(at: at(1)) == idle, "pausing an idle stopwatch does nothing")
    expect(idle.resumed(at: at(1)) == idle, "resuming an idle stopwatch does nothing")

    let running = StopwatchState.started(at: at(0))
    expect(running.isRunning && !running.isIdle, "starting runs it")
    expect(running.elapsed(at: at(12.5)) == 12.5, "elapsed is time since start")
    expect(running.elapsed(at: at(-3)) == 0, "a clock that steps backwards reads zero, not negative")

    let paused = running.paused(at: at(10))
    expect(paused.isPaused && !paused.isRunning, "pausing stops it")
    expect(paused.elapsed(at: at(500)) == 10, "a paused stopwatch holds its reading")
    expect(paused.paused(at: at(600)) == paused, "pausing twice changes nothing")

    // Paused for 90 seconds, then resumed: those 90 seconds don't count.
    let resumed = paused.resumed(at: at(100))
    expect(resumed.isRunning, "resuming runs it again")
    expect(resumed.elapsed(at: at(100)) == 10, "it picks up where it stopped")
    expect(resumed.elapsed(at: at(105)) == 15, "and keeps counting from there")
    expect(resumed.origin == at(90), "the origin shifts by the time spent paused")

    // Paused the instant it started is still paused, not idle.
    let instant = StopwatchState.started(at: at(0)).paused(at: at(0))
    expect(instant.isPaused && !instant.isIdle, "a stopwatch paused at zero is paused, not reset")

    expect(StopwatchState.clock(0) == "0:00", "zero reads 0:00")
    expect(StopwatchState.clock(0.9) == "0:00", "the first second isn't claimed early")
    expect(StopwatchState.clock(61.2) == "1:01", "minutes and seconds")
    expect(StopwatchState.clock(3600) == "1:00:00", "an hour gains the hours field")
    expect(StopwatchState.clock(-5) == "0:00", "negative reads zero")
}
