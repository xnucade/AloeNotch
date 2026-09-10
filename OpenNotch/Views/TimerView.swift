import SwiftUI

/// The timer module. A ring while one is running, presets when none is.
///
/// `compact` is the tabbed column; the roomy version is the one-module layout.
/// Both draw the same ring — only the scale and the number of presets differ.
struct TimerView: View {
    @ObservedObject var timer: TimerModel
    var compact = true
    var showsHeader = true

    @ObservedObject private var settings = AppSettings.shared

    private var ringSize: CGFloat { compact ? 54 : 104 }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader { header }

            Group {
                if timer.finishedAt != nil {
                    finished
                } else if timer.isActive {
                    running
                } else {
                    idle
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Motion.contentFade, value: timer.isActive)
        .animation(Motion.contentFade, value: timer.finishedAt)
    }

    private var header: some View {
        HStack {
            Text("Timer")
                .font(Typography.micro(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if timer.isActive { TimerCancelButton { timer.cancel() } }
        }
    }

    // MARK: Faces

    /// Nothing running: the presets, and a repeat of whatever was last used.
    private var idle: some View {
        VStack(spacing: compact ? Metrics.Spacing.snug : Metrics.Spacing.regular) {
            // The compact column has room for four chips on one line; the wide
            // layout takes all five and can afford the label above them.
            if !compact {
                Text("Start a timer")
                    .font(Typography.body(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if compact {
                // Two by two. Four chips across 160pt wrap into circles, and a
                // wrapped pill is unreadable at this size.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Metrics.Spacing.tight),
                                    GridItem(.flexible(), spacing: Metrics.Spacing.tight)],
                          spacing: Metrics.Spacing.tight) {
                    ForEach(TimerModel.presets.prefix(4), id: \.self) { seconds in
                        chip(seconds)
                    }
                }
            } else {
                HStack(spacing: Metrics.Spacing.tight) {
                    ForEach(TimerModel.presets, id: \.self) { seconds in
                        chip(seconds)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chip(_ seconds: TimeInterval) -> some View {
        PresetChip(label: CountdownState.label(seconds), accent: settings.accent) {
            timer.start(seconds)
        }
    }

    private var running: some View {
        // One timeline for the whole face, so the ring and the digits are read
        // from the same instant and cannot disagree by a frame.
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            let remaining = timer.state.remaining(at: now)

            HStack(spacing: compact ? Metrics.Spacing.regular : Metrics.Spacing.loose) {
                CountdownRing(progress: timer.state.progress(at: now),
                              remaining: remaining,
                              paused: timer.state.isPaused,
                              size: ringSize,
                              accent: settings.accent)

                VStack(alignment: .leading, spacing: Metrics.Spacing.tight) {
                    if !compact {
                        Text(timer.state.isPaused ? "Paused" : "Counting down")
                            .font(Typography.caption())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: Metrics.Spacing.tight) {
                        TimerControl(symbol: timer.state.isPaused ? "play.fill" : "pause.fill",
                                     prominent: true) {
                            timer.state.isPaused ? timer.resume() : timer.pause()
                        }
                        TimerControl(symbol: "goforward.60") { timer.extend(by: 60) }
                            .help("Add a minute")
                        // No cancel here. Whoever draws the header draws it —
                        // this view when it owns the header, the tabbed column
                        // when it doesn't — so there is exactly one X on screen
                        // either way.
                    }
                }
                .fixedSize(horizontal: !compact, vertical: false)

                if compact { Spacer(minLength: 0) }
            }
            // Centred when it has the whole panel: a 92pt ring hard against the
            // left edge of 680pt of black reads as something that failed to
            // load. In the column there is no spare width to centre in.
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: compact ? .leading : .center)
        }
    }

    /// Held until acknowledged. A timer that finishes while you are in another
    /// app and clears itself has told you nothing.
    private var finished: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            Image(systemName: "bell.fill")
                .font(Typography.icon(compact ? 18 : 26, .medium))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeat(3))
            Text("Time's up")
                .font(Typography.body(.semibold))
            HStack(spacing: Metrics.Spacing.tight) {
                PresetChip(label: "Again", accent: settings.accent) {
                    timer.start(timer.lastDuration)
                }
                PresetChip(label: "Done", accent: .white.opacity(0.5)) {
                    timer.acknowledge()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The trash-equivalent for the tabbed column's header row.
struct TimerCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Cancel the timer")
    }
}

// MARK: - The ring

/// Progress as a ring with the remaining time inside it.
///
/// The ring fills clockwise from twelve because that is the direction every
/// physical timer has ever moved, and it is drawn with a `.linear` animation
/// rather than a spring: a spring on a clock overshoots, which means the ring
/// briefly claims more time has passed than has.
private struct CountdownRing: View {
    let progress: Double
    let remaining: TimeInterval
    let paused: Bool
    let size: CGFloat
    let accent: Color

    @Environment(\.notchReduceMotion) private var reduceMotion

    /// The last ten seconds pulse. It is the only moment where the number alone
    /// is not enough — you are watching for it to hit zero.
    private var isFinalStretch: Bool { remaining <= 10 && !paused }

    private var lineWidth: CGFloat { max(3, size * 0.075) }

    /// The fraction of the circle whose arc length equals the stroke width.
    private var minimumVisibleArc: Double {
        Double(lineWidth / (.pi * size))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(isFinalStretch ? Color.orange : accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // A round cap on a very short arc paints a lone dot at twelve
                // o'clock, which reads as a rendering fault rather than as
                // "barely started". Hidden until the arc is at least as long
                // as the cap is wide and therefore looks like an arc.
                .opacity(progress > minimumVisibleArc ? 1 : 0)
                .animation(.linear(duration: 0.25), value: progress)

            Text(CountdownState.clock(remaining))
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(Motion.readout, value: Int(remaining.rounded(.up)))
                .foregroundStyle(.white.opacity(paused ? 0.5 : 0.95))
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: Int(remaining.rounded(.up)))
        .opacity(paused ? 0.75 : 1)
    }

    /// A half-second breath on each of the last ten seconds. Under Reduce
    /// Motion the colour change still marks the final stretch.
    private var pulse: CGFloat {
        guard isFinalStretch, !reduceMotion else { return 1 }
        return Int(remaining.rounded(.up)) % 2 == 0 ? 1.0 : 1.045
    }
}

// MARK: - Controls

private struct PresetChip: View {
    let label: String
    let accent: Color
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.micro(.semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(hovering ? .white : .white.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(hovering ? accent.opacity(0.30) : .white.opacity(0.09))
                }
                .overlay {
                    Capsule().strokeBorder(accent.opacity(hovering ? 0.55 : 0), lineWidth: 1)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

private struct TimerControl: View {
    let symbol: String
    var prominent = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private var diameter: CGFloat { prominent ? 30 : 26 }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.icon(prominent ? 13 : 11, .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(.white.opacity(prominent
                                                 ? (hovering ? 0.20 : 0.13)
                                                 : (hovering ? 0.13 : 0.06)))
                }
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(reduceMotion ? 1 : (hovering ? 1.06 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}
