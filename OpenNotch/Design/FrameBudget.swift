#if DEBUG
import AppKit
import OSLog

/// Debug-only: measures the frames of each panel transition and logs the
/// worst one, so "never drops a frame" is a number rather than a feeling.
///
/// A display link on the panel's screen records every frame while a
/// transition runs. A frame that took more than 1.5× the display's interval
/// is a drop. Read the results with:
///
///     log stream --predicate 'subsystem == "com.kadeslab.AloeNotch" && category == "frames"'
///
/// Compiled out of Release builds entirely.
final class FrameBudget: NSObject {
    static let shared = FrameBudget()

    private let log = Logger(subsystem: "com.kadeslab.AloeNotch", category: "frames")
    private var link: CADisplayLink?
    private var label = ""
    private var last: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0
    private var frames = 0
    private var drops = 0
    private var interval: CFTimeInterval = 1.0 / 120
    private var stopWork: DispatchWorkItem?

    /// Watch the next `duration` seconds of frames on `screen`. A new
    /// transition arriving mid-watch reports the old one and starts over.
    func watch(_ label: String, on screen: NSScreen?, for duration: TimeInterval) {
        if link != nil { report() }
        guard let screen = screen ?? NSScreen.main else { return }
        self.label = label
        last = 0; worst = 0; frames = 0; drops = 0
        interval = 1.0 / Double(max(60, screen.maximumFramesPerSecond))
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.report() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard last > 0 else { return }
        let delta = now - last
        frames += 1
        worst = max(worst, delta)
        if delta > interval * 1.5 { drops += 1 }
    }

    private func report() {
        link?.invalidate()
        link = nil
        guard frames > 0 else { return }
        let worstMs = worst * 1000, budgetMs = interval * 1000
        let verdict = drops == 0 ? "OK" : "DROPPED \(drops)"
        log.notice("\(self.label, privacy: .public): \(verdict, privacy: .public) — \(self.frames) frames, worst \(worstMs, format: .fixed(precision: 1)) ms (budget \(budgetMs, format: .fixed(precision: 1)) ms)")
    }
}
#endif
