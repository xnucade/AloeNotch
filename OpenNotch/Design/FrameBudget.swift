import AppKit
import OSLog

/// Measures the frames of each panel transition and reports the worst one,
/// so "never drops a frame" is a number rather than a feeling.
///
/// A display link on the panel's screen records every frame while a
/// transition runs. A frame that took more than 1.5× the display's interval
/// is a drop. Debug builds always log the results; read them with:
///
///     log stream --predicate 'subsystem == "com.kadeslab.AloeNotch" && category == "frames"'
///
/// Release builds carry it for the frame-time overlay in the debug menu, and
/// do nothing until that overlay is switched on: no display link, no work.
final class FrameBudget: NSObject, ObservableObject {
    static let shared = FrameBudget()

    struct Result: Equatable {
        let label: String
        let frames: Int
        let drops: Int
        let worstMs: Double
        let budgetMs: Double
    }

    /// The most recent finished transition, for the overlay.
    @Published private(set) var last: Result?

    /// Set by the debug menu's benchmark for the length of a run.
    var forceEnabled = false

    private var isEnabled: Bool {
        #if DEBUG
        true
        #else
        forceEnabled || DebugTools.shared.showFrameTimes
        #endif
    }

    private let log = Logger(subsystem: "com.kadeslab.AloeNotch", category: "frames")
    private var link: CADisplayLink?
    private var label = ""
    private var lastTick: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0
    private var frames = 0
    private var drops = 0
    private var interval: CFTimeInterval = 1.0 / 120
    private var stopWork: DispatchWorkItem?

    /// Watch the next `duration` seconds of frames on `screen`. A new
    /// transition arriving mid-watch reports the old one and starts over.
    func watch(_ label: String, on screen: NSScreen?, for duration: TimeInterval) {
        guard isEnabled else { return }
        if link != nil { report() }
        guard let screen = screen ?? NSScreen.main else { return }
        self.label = label
        lastTick = 0; worst = 0; frames = 0; drops = 0
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
        defer { lastTick = now }
        guard lastTick > 0 else { return }
        let delta = now - lastTick
        frames += 1
        worst = max(worst, delta)
        if delta > interval * 1.5 { drops += 1 }
    }

    private func report() {
        link?.invalidate()
        link = nil
        guard frames > 0 else { return }
        let result = Result(label: label, frames: frames, drops: drops,
                            worstMs: worst * 1000, budgetMs: interval * 1000)
        last = result
        let verdict = drops == 0 ? "OK" : "DROPPED \(drops)"
        log.notice("\(result.label, privacy: .public): \(verdict, privacy: .public) — \(result.frames) frames, worst \(result.worstMs, format: .fixed(precision: 1)) ms (budget \(result.budgetMs, format: .fixed(precision: 1)) ms)")
    }
}
