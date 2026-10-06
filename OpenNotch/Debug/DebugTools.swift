import AppKit
import SwiftUI
import Combine

/// The tools behind the hidden debug section of the menu bar dropdown
/// (⌥-click the icon): slow motion, a state cycler, and a frame-time overlay.
///
/// Compiled into Release on purpose, so the shipping build can be checked
/// the same way. Nothing here is remembered across launches: a slow-motion
/// setting left on by accident would read as the app being broken.
final class DebugTools: ObservableObject {
    static let shared = DebugTools()

    static let slowMotionRange: ClosedRange<Double> = 0.1...1

    /// Multiplier on every `Motion` duration. 1 is normal speed.
    @Published var slowMotion: Double = 1

    @Published var showFrameTimes = false {
        didSet { showFrameTimes ? FrameOverlay.shared.show() : FrameOverlay.shared.hide() }
    }

    /// The step the cycler last ran, if it is driving the panel.
    @Published private(set) var step: Step?

    /// Set by the app delegate once the panel exists.
    weak var viewModel: NotchViewModel?

    /// Anything left switched on. Keeps the section visible without ⌥, so a
    /// tool can always be turned back off.
    var isActive: Bool { slowMotion != 1 || showFrameTimes || step != nil }

    // MARK: Benchmark

    /// The last benchmark's summary, one line per style.
    @Published private(set) var benchmark: String?
    @Published private(set) var isBenchmarking = false
    private var collected: [FrameBudget.Result] = []
    private var collecting: AnyCancellable?

    /// Opens and closes the panel a few times as Solid, then as Glass, and
    /// reports frame times and the app's own CPU time for each. The cost of
    /// glass was a guess until this.
    func runBenchmark(cycles: Int = 3) {
        guard let viewModel, !isBenchmarking else { return }
        clear(viewModel)
        step = nil
        isBenchmarking = true
        benchmark = nil

        let settings = AppSettings.shared
        let original = settings.notchStyle
        let budget = FrameBudget.shared
        budget.forceEnabled = true
        collecting = budget.$last.compactMap { $0 }.sink { [weak self] in self?.collected.append($0) }

        Task { @MainActor in
            var lines: [String] = []
            let open = Motion.settle(Motion.Duration.expand) + 0.3
            let close = Motion.settle(Motion.Duration.collapse) + 0.3
            for style in NotchStyle.allCases {
                settings.notchStyle = style
                try? await Task.sleep(for: .seconds(0.4))
                collected = []
                let cpuBefore = Self.cpuTime()
                for _ in 0..<cycles {
                    viewModel.debugPin(true)
                    try? await Task.sleep(for: .seconds(open))
                    viewModel.debugPin(false)
                    try? await Task.sleep(for: .seconds(close))
                }
                let cpu = (Self.cpuTime() - cpuBefore) * 1000 / Double(cycles)
                lines.append(Self.summary(style.title, collected, cpuPerCycle: cpu))
            }
            settings.notchStyle = original
            budget.forceEnabled = false
            collecting = nil
            if AccessibilityPreferences.shared.reduceTransparency {
                lines.append("Reduce Transparency is on, so Glass drew as Solid.")
            }
            benchmark = lines.joined(separator: "\n")
            isBenchmarking = false
            NSLog("AloeNotch benchmark:\n%@", benchmark ?? "")
        }
    }

    private static func summary(_ name: String, _ results: [FrameBudget.Result], cpuPerCycle: Double) -> String {
        func worst(_ rs: [FrameBudget.Result]) -> String {
            String(format: "%.1f", rs.map(\.worstMs).max() ?? 0)
        }
        let opens = results.filter { $0.label.hasSuffix("expanded") }
        let closes = results.filter { !$0.label.hasSuffix("expanded") }
        let drops = results.reduce(0) { $0 + $1.drops }
        let budget = String(format: "%.1f", results.first?.budgetMs ?? 0)
        return "\(name): open \(worst(opens)) / close \(worst(closes)) ms worst (budget \(budget)), "
            + "\(drops) dropped, \(String(format: "%.0f", cpuPerCycle)) ms CPU per cycle"
    }

    /// User plus system CPU time used by this process so far, in seconds.
    private static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Every panel state, then the one-shot modifiers that play on top of a
    /// state. Each step leaves the panel where the next one expects it.
    enum Step: Int, CaseIterable, Identifiable {
        case compact, regular, wide, split, expanded, limitPush, gulp, pull, collapsed

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .compact:   "Peek · compact"
            case .regular:   "Peek · regular"
            case .wide:      "Peek · wide"
            case .split:     "Split (needs music playing)"
            case .expanded:  "Expanded"
            case .limitPush: "Level pushed past its stop"
            case .gulp:      "Drop gulp"
            case .pull:      "Two-finger pull"
            case .collapsed: "Collapsed"
            }
        }

        var next: Step { Step(rawValue: rawValue + 1) ?? Step.allCases[0] }
    }

    func advance() { run(step?.next ?? Step.allCases[0]) }

    func run(_ step: Step) {
        guard let viewModel else { return }
        let activities = viewModel.activities
        self.step = step

        switch step {
        case .compact:
            clear(viewModel)
            activities.present(demo(symbol: "bell.fill", size: .compact))
        case .regular:
            clear(viewModel)
            activities.present(demo(symbol: "bolt.fill", tint: .green, trailing: .text("82%"), size: .regular))
        case .wide:
            clear(viewModel)
            activities.present(demo(symbol: "speaker.wave.2.fill", trailing: .level(0.6), size: .wide))
        case .split:
            clear(viewModel)
            activities.setResident(LiveActivity(
                kind: Self.residentKind, symbol: "timer", tint: .orange,
                spokenName: "Debug timer", trailing: .countdown(Date().addingTimeInterval(300)),
                size: .regular, duration: .infinity))
        case .expanded:
            clear(viewModel)
            viewModel.debugPin(true)
        case .limitPush:
            clear(viewModel)
            activities.present(demo(symbol: "speaker.wave.3.fill", trailing: .level(1), size: .wide))
            // Let the readout arrive before pushing against it.
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.settle(Motion.Duration.hud)) {
                activities.pushAgainstLimit(1)
            }
        case .gulp:
            clear(viewModel)
            viewModel.debugPin(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.settle(Motion.Duration.expand)) {
                viewModel.debugGulp()
            }
        case .pull:
            clear(viewModel)
            viewModel.debugPull()
        case .collapsed:
            clear(viewModel)
        }
    }

    /// Put everything back: normal speed, no overlay, panel released.
    func reset() {
        if let viewModel { clear(viewModel) }
        step = nil
        slowMotion = 1
        showFrameTimes = false
    }

    private static let kind = "debug"
    private static let residentKind = "debug.resident"

    private func clear(_ viewModel: NotchViewModel) {
        viewModel.debugPin(false)
        viewModel.activities.dismiss(kind: Self.kind)
        viewModel.activities.clearResident(kind: Self.residentKind)
    }

    /// Held for an hour rather than the usual two seconds, so a step stays
    /// put until the next one replaces it — at 0.1× an arrival alone is
    /// several seconds long.
    private func demo(symbol: String, tint: Color = .white,
                      trailing: LiveActivity.Trailing = .none,
                      size: PanelState.ActivitySize) -> LiveActivity {
        LiveActivity(kind: Self.kind, symbol: symbol, tint: tint, spokenName: "Debug",
                     trailing: trailing, size: size, duration: 3600,
                     priority: LiveActivity.Priority.direct)
    }
}

/// A small readout of the last transition's frame times, in the screen's
/// top-left corner under the menu bar. Never takes the mouse.
final class FrameOverlay {
    static let shared = FrameOverlay()

    private var panel: NSPanel?

    func show() {
        let size = CGSize(width: 300, height: 44)
        let screen = NotchGeometry.preferredScreen()
        let origin = CGPoint(x: screen.frame.minX + 12,
                             y: screen.visibleFrame.maxY - size.height - 8)
        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: CGRect(origin: origin, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .init(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.contentView = NSHostingView(rootView: FrameOverlayView())
            return panel
        }()
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }
}

private struct FrameOverlayView: View {
    @ObservedObject private var budget = FrameBudget.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = budget.last {
                Text(last.label)
                    .foregroundStyle(.secondary)
                Text(verdict(last))
                    .foregroundStyle(last.drops == 0 ? Color.green : Color.orange)
            } else {
                Text("Frame times: waiting for a transition")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
    }

    private func verdict(_ r: FrameBudget.Result) -> String {
        let head = r.drops == 0 ? "OK" : "\(r.drops) dropped"
        return "\(head) · \(r.frames) frames · worst \(String(format: "%.1f", r.worstMs)) / \(String(format: "%.1f", r.budgetMs)) ms"
    }
}
