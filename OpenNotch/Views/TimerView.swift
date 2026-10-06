import SwiftUI

/// The timer module: a countdown, a stopwatch or a focus session.
///
/// `compact` is the tabbed column; the roomy version is the one-module layout.
/// Every mode draws the same ring — only what it measures, the scale and the
/// number of presets differ.
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
                } else if timer.isActive || timer.mode != .timer {
                    face
                } else {
                    presets
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Motion.contentFade, value: timer.isActive)
        .animation(Motion.contentFade, value: timer.finishedAt)
        .animation(Motion.contentFade, value: timer.mode)
    }

    private var header: some View {
        HStack {
            Text(timer.mode.label)
                .font(Typography.micro(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Ink.tertiary)
                .contentTransition(.opacity)
            Spacer()
            if timer.isActive { TimerCancelButton { timer.cancel() } }
        }
    }

    /// Only offered when nothing is running or waiting to be acknowledged —
    /// switching away from a live clock would strand it.
    private var showsPicker: Bool { !timer.isActive && timer.finishedAt == nil }

    // MARK: Faces

    /// Timer mode with nothing running: the presets, and a repeat of
    /// whatever was last used.
    private var presets: some View {
        VStack(spacing: compact ? Metrics.Spacing.snug : Metrics.Spacing.regular) {
            TimerModePicker(timer: timer, compact: compact, accent: settings.accent)

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

    /// The ring and its controls — running, paused, or (for the stopwatch
    /// and focus, which have nothing to pick) waiting at zero to be started.
    private var face: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            if showsPicker {
                TimerModePicker(timer: timer, compact: compact, accent: settings.accent)
            }
            if timer.mode == .stopwatch {
                // Ticks from the origin so each redraw lands on a second.
                TimelineView(.periodic(from: timer.stopwatch.origin ?? .now, by: 1)) { context in
                    stopwatchFace(at: context.date)
                }
            } else {
                // One timeline for the whole face, so the ring and the digits
                // are read from the same instant and cannot disagree by a
                // frame.
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    countdownFace(at: context.date)
                }
            }
        }
    }

    private func countdownFace(at now: Date) -> some View {
        let idle = timer.state.isIdle
        let remaining = idle ? TimerModel.focusLength : timer.state.remaining(at: now)
        let resting = timer.focusPhase == .rest
        let caption: LocalizedStringKey = switch (timer.focusPhase, timer.state.isPaused) {
        case (_, true):      "Paused"
        case (.focus?, _):   "Focusing"
        case (.rest?, _):    "On a break"
        case (nil, _):       idle ? "25 min focus, 5 min break" : "Counting down"
        }
        return layout(
            ring: ClockRing(progress: idle ? 0 : timer.state.progress(at: now),
                            label: CountdownState.clock(remaining),
                            urgentTick: !idle && remaining <= 10 ? Int(remaining.rounded(.up)) : nil,
                            paused: timer.state.isPaused,
                            size: ringSize,
                            accent: resting ? .green : settings.accent),
            caption: caption,
            controls: {
                if idle {
                    TimerControl(symbol: "play.fill", prominent: true) { timer.startFocus() }
                        .accessibilityLabel("Start focus")
                } else {
                    pauseResume
                    TimerControl(symbol: "goforward.60") { timer.extend(by: 60) }
                        .help("Add a minute")
                        .accessibilityLabel("Add a minute")
                }
            })
    }

    private func stopwatchFace(at now: Date) -> some View {
        let sw = timer.stopwatch
        let elapsed = sw.elapsed(at: now)
        let second = Int(elapsed.rounded(.down)) % 60
        return layout(
            // A seconds hand rather than progress — a stopwatch has no end to
            // be a fraction of. Snaps back at the top of each minute instead
            // of unwinding through the whole circle.
            ring: ClockRing(progress: Double(second) / 60,
                            label: StopwatchState.clock(elapsed),
                            countsDown: false,
                            animatesProgress: second != 0,
                            paused: sw.isPaused,
                            size: ringSize,
                            accent: settings.accent),
            caption: sw.isIdle ? "Ready" : (sw.isPaused ? "Paused" : "Counting up"),
            controls: {
                if sw.isIdle {
                    TimerControl(symbol: "play.fill", prominent: true) { timer.startStopwatch() }
                        .accessibilityLabel("Start stopwatch")
                } else {
                    pauseResume
                }
            })
    }

    private var pauseResume: some View {
        TimerControl(symbol: timer.isPaused ? "play.fill" : "pause.fill", prominent: true) {
            timer.isPaused ? timer.resume() : timer.pause()
        }
        .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
    }

    private func layout<Controls: View>(ring: ClockRing,
                                        caption: LocalizedStringKey,
                                        @ViewBuilder controls: () -> Controls) -> some View {
        HStack(spacing: compact ? Metrics.Spacing.regular : Metrics.Spacing.loose) {
            ring

            VStack(alignment: .leading, spacing: Metrics.Spacing.tight) {
                if !compact {
                    Text(caption)
                        .font(Typography.caption())
                        .foregroundStyle(Ink.tertiary)
                }
                // No cancel here. Whoever draws the header draws it — this
                // view when it owns the header, the tabbed column when it
                // doesn't — so there is exactly one X on screen either way.
                HStack(spacing: Metrics.Spacing.tight) { controls() }
            }
            .fixedSize(horizontal: !compact, vertical: false)

            if compact { Spacer(minLength: 0) }
        }
        // Centred when it has the whole panel: a 92pt ring hard against the
        // left edge of 680pt of black reads as something that failed to load.
        // In the column there is no spare width to centre in.
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: compact ? .leading : .center)
    }

    /// Held until acknowledged. A timer that finishes while you are in another
    /// app and clears itself has told you nothing.
    private var finished: some View {
        let focus = timer.mode == .focus
        return VStack(spacing: Metrics.Spacing.snug) {
            Image(systemName: focus ? "brain.head.profile" : "bell.fill")
                .font(Typography.icon(compact ? 18 : 26, .medium))
                .foregroundStyle(focus ? Ink.primary : Color.orange)
                .symbolEffect(.bounce, options: .repeat(3))
            Text(focus ? "Break's over" : "Time's up")
                .font(Typography.label(.semibold))
            HStack(spacing: Metrics.Spacing.tight) {
                PresetChip(label: focus ? String(localized: "Start focus") : String(localized: "Again"),
                           accent: settings.accent) {
                    focus ? timer.startFocus() : timer.start(timer.lastDuration)
                }
                PresetChip(label: String(localized: "Done"), accent: Ink.tertiary) {
                    timer.acknowledge()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Timer, stopwatch, focus. Glyphs alone in the column, where three labels
/// don't fit; glyph and label when the module has the panel to itself.
private struct TimerModePicker: View {
    @ObservedObject var timer: TimerModel
    let compact: Bool
    let accent: Color

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimerModel.Mode.allCases) { mode in
                let isOn = timer.mode == mode
                Button {
                    withAnimation(Motion.micro) { timer.mode = mode }
                } label: {
                    HStack(spacing: Metrics.Spacing.tight) {
                        Image(systemName: mode.symbol)
                            .font(Typography.icon(10, .semibold))
                        if !compact {
                            Text(mode.label).font(Typography.micro(.semibold))
                        }
                    }
                    .foregroundStyle(isOn ? Ink.primary : Ink.tertiary)
                    .frame(maxWidth: compact ? .infinity : nil)
                    .padding(.horizontal, compact ? 0 : Metrics.Pill.horizontalPadding)
                    .padding(.vertical, 4)
                    .background {
                        if isOn {
                            Capsule().fill(Ink.fillStrong)
                                .matchedGeometryEffect(id: "mode", in: selection)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(PressableButtonStyle())
                .help(mode.label)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Ink.fill))
        .fixedSize(horizontal: !compact, vertical: true)
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
        .help("Stop and reset")
        .accessibilityLabel("Stop and reset")
    }
}

// MARK: - The ring

/// Progress as a ring with the time inside it.
///
/// The ring fills clockwise from twelve because that is the direction every
/// physical timer has ever moved, and it is drawn with a `.linear` animation
/// rather than a spring: a spring on a clock overshoots, which means the ring
/// briefly claims more time has passed than has.
private struct ClockRing: View {
    let progress: Double
    let label: String
    var countsDown = true
    /// The whole second, during a countdown's last ten; nil otherwise. Drives
    /// the colour change and the pulse.
    var urgentTick: Int?
    /// Off for the frame a stopwatch's hand returns to twelve.
    var animatesProgress = true
    let paused: Bool
    let size: CGFloat
    let accent: Color

    @Environment(\.notchReduceMotion) private var reduceMotion

    /// The last ten seconds pulse. It is the only moment where the number alone
    /// is not enough — you are watching for it to hit zero.
    private var isFinalStretch: Bool { urgentTick != nil && !paused }

    private var lineWidth: CGFloat { max(3, size * 0.075) }

    /// The fraction of the circle whose arc length equals the stroke width.
    private var minimumVisibleArc: Double {
        Double(lineWidth / (.pi * size))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Ink.fillStrong, lineWidth: lineWidth)

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
                .animation(animatesProgress ? Motion.ringProgress : nil, value: progress)

            Text(label)
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, lineWidth)
                .contentTransition(.numericText(countsDown: countsDown))
                .animation(Motion.readout, value: label)
                .foregroundStyle(paused ? Ink.tertiary : Ink.primary)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .animation(reduceMotion ? nil : Motion.finishedPulse, value: urgentTick)
        .opacity(paused ? 0.75 : 1)
    }

    /// A half-second breath on each of the last ten seconds. Under Reduce
    /// Motion the colour change still marks the final stretch.
    private var pulse: CGFloat {
        guard isFinalStretch, !reduceMotion, let urgentTick else { return 1 }
        return urgentTick % 2 == 0 ? 1.0 : 1.045
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
                .foregroundStyle(hovering ? .white : Ink.primary)
                .padding(.horizontal, Metrics.Pill.horizontalPadding)
                .padding(.vertical, Metrics.Pill.verticalPadding)
                .background {
                    Capsule().fill(hovering ? accent.opacity(0.30) : Ink.fill)
                }
                .overlay {
                    Capsule().strokeBorder(accent.opacity(hovering ? 0.55 : 0), lineWidth: 1)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.micro) {
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
                .foregroundStyle(hovering ? .white : Ink.primary)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(prominent
                                  ? (hovering ? Ink.fillBright : Ink.fillStrong)
                                  : (hovering ? Ink.fillStrong : Ink.fill))
                }
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(reduceMotion ? 1 : (hovering ? 1.06 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.micro) {
                hovering = inside
            }
        }
    }
}
