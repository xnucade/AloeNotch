import SwiftUI

/// The whole notch surface. Collapsed it is a thin black strip that blends into
/// the hardware notch (with small "wings" for glanceable indicators); expanded
/// it drops down into a rounded panel with the clock, weather, media controls,
/// drop shelf, calendar, and battery.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    /// Observed directly rather than read from the environment: the panel is
    /// mounted in a bare NSHostingView rather than a SwiftUI scene, so SwiftUI
    /// does not populate `\.accessibilityReduceMotion` here. This view both
    /// reads the values and republishes them to its children.
    @ObservedObject private var a11y = AccessibilityPreferences.shared
    @State private var isDropTargeted = false

    /// Namespace for the shared artwork element. See `sharedArtwork`.
    @Namespace private var morph

    private var metrics: NotchMetrics? { viewModel.metrics }
    private var state: PanelState { viewModel.panelState }

    /// Peek the now-playing glyph out beside the notch while something plays.
    /// Now read from the state machine rather than re-derived here, so the
    /// drawn surface and the clickable region can't disagree.
    private var showMediaGlyph: Bool { state == .peek(.media) }

    /// The surface's current on-screen size, straight from the one function
    /// that decides it (`NotchMetrics.size(for:)`).
    private var surfaceSize: CGSize {
        metrics?.size(for: state) ?? NotchGeometry.simulatedNotchSize
    }

    /// Height of the collapsed strip — i.e. the hardware notch. Constant across
    /// states (wings only ever change width), and used to push expanded content
    /// clear of the physical cutout.
    private var stripHeight: CGFloat {
        metrics?.notchSize.height ?? NotchGeometry.simulatedNotchSize.height
    }

    private var hasHardwareNotch: Bool {
        metrics?.hasHardwareNotch ?? false
    }

    // MARK: Shared artwork geometry
    //
    // The artwork is a matched pair: a real image in the peek strip and a real
    // image in the expanded panel, both carrying `artworkID` in the `morph`
    // namespace. SwiftUI treats a matched insert/remove pair as one element and
    // explicitly interpolates the frame between them.
    //
    // An earlier attempt used one persistent image with `isSource: false`,
    // anchored to invisible placeholders in each branch, on the theory that a
    // single never-removed view could not cross-fade. It positioned correctly
    // but would not animate: with a separate follower, the position is read
    // from whichever source currently exists, so when the source *changes
    // identity* across the branch swap the frame changes discretely — and
    // geometry-derived values are not interpolated. The pair below is the
    // pattern SwiftUI actually animates.
    //
    // The cross-fade that motivated the original detour is a non-issue here:
    // both views draw the *same* image, so dissolving between them at a shared
    // interpolated frame is indistinguishable from a single moving view.

    var body: some View {
        VStack(spacing: 0) {
            notchSurface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .withAccessibilityPreferences()
    }

    private var notchSurface: some View {
        let radius = Metrics.radius(expanded: state.isExpanded)
        return ZStack {
            panelFill

            Group {
                if state.isExpanded {
                    ExpandedContent(viewModel: viewModel, morph: morph)
                        .padding(.horizontal, Metrics.panelHorizontalInset)
                        // Clear the physical notch.
                        .padding(.top, stripHeight + Metrics.contentTopGap)
                        .padding(.bottom, Metrics.panelBottomInset)
                        // Insert as identity so the rows' own staggered
                        // arrivals are visible (see NotchEntrance).
                        //
                        // Leaving, everything goes at once — a reverse cascade
                        // reads as the panel struggling to close. The scale
                        // matters more than it looks: with a plain opacity
                        // removal the content was gone while the pill was still
                        // at full size, leaving an empty black rectangle to
                        // shrink on its own. Scaling toward the notch on the
                        // same curve as the container keeps the contents
                        // attached to the shape that is carrying them.
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity
                                .combined(with: .scale(scale: 0.94, anchor: .top))
                                .animation(Motion.collapse)
                        ))
                } else if state == .peek(.charging) {
                    ChargingContent(
                        battery: viewModel.battery,
                        deadZone: hasHardwareNotch ? (metrics?.notchSize.width ?? 0) : 0
                    )
                    .padding(.horizontal, hasHardwareNotch ? Metrics.hudInsetHardware
                                                           : Metrics.hudInsetSimulated)
                    .transition(.notchEntrance(reduceMotion: a11y.reduceMotion))
                } else if state == .peek(.hud), let hud = viewModel.hud {
                    // A system readout takes over the strip while it's showing.
                    // Keyed on the state, not just `hud != nil`, so the content
                    // drawn always matches the width the state machine sized
                    // the strip for.
                    HUDContent(hud: hud,
                               deadZone: hasHardwareNotch ? (metrics?.notchSize.width ?? 0) : 0)
                        .padding(.horizontal, hasHardwareNotch ? Metrics.hudInsetHardware
                                                              : Metrics.hudInsetSimulated)
                        .transition(.notchEntrance(reduceMotion: a11y.reduceMotion))
                } else {
                    // On a hardware notch this only draws while media plays (in
                    // the wings that peek out either side); otherwise it renders
                    // nothing and the strip stays invisible.
                    CollapsedContent(
                        media: viewModel.media,
                        battery: viewModel.battery,
                        deadZone: hasHardwareNotch ? (metrics?.notchSize.width ?? 0) : 0,
                        showMediaGlyph: showMediaGlyph,
                        showBattery: settings.showBattery,
                        morph: morph
                    )
                    .padding(.horizontal, hasHardwareNotch ? Metrics.stripInsetHardware
                                                           : Metrics.stripInsetSimulated)
                    .transition(.notchEntrance(reduceMotion: a11y.reduceMotion))
                }
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        // Clip AFTER the frame so the clip bounds follow the animating size.
        // (Clipping the inner Group instead sized the clip to the *content*, so
        // collapsing left the outgoing panel ghosted at full width outside the
        // notch.) This also keeps inner light effects inside the panel.
        .clipShape(NotchShape(cornerRadius: radius))
        // Glow lives outside the clip so its bloom can still extend past the edge.
        .background {
            if settings.ambientGlow {
                AmbientGlow(
                    media: viewModel.media,
                    radius: radius,
                    isExpanded: state.isExpanded
                )
            }
        }
        // The one animation driving the whole surface: frame, corner radius,
        // the content branch transitions, and the matched artwork all move
        // under this. The curve comes from the view model, which picks it per
        // transition (bouncier opening, settled closing, quick between peeks).
        .animation(viewModel.stateAnimation, value: state)
        .contentShape(Rectangle())
        .onHover { viewModel.hoverChanged($0) }
        // Dragging a file over the collapsed strip opens the shelf; dropping
        // directly on the strip stages it immediately.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            let accepted = viewModel.tray.handleDrop(providers)
            if accepted { Haptics.caught() }
            return accepted
        }
        .onChange(of: isDropTargeted) { _, targeted in
            viewModel.hoverChanged(targeted || state.isExpanded)
        }
    }

    /// Matched-geometry id for the artwork, shared by CollapsedContent and MediaView.
    static let artworkID = "notch.artwork"

    // The window has `NotchMetrics.shadowMargin` of transparent room on the
    // sides and bottom, so the shadow can blur out fully instead of being
    // clipped into corner artifacts. Keep its extent (radius + y offset) well
    // inside that margin.
    private var panelFill: some View {
        // Same source as the clip shape above (Metrics.radius), so the fill and
        // the clip can never disagree about the silhouette they are drawing.
        let radius = Metrics.radius(expanded: state.isExpanded)
        return NotchShape(cornerRadius: radius)
            .fill(.black)
            .overlay {
                // Hairline edge on the sides and bottom only. Nothing light may
                // touch the top region: the fill must stay pure black there so
                // the hardware notch cutout is indistinguishable from the panel.
                //
                // Strokes the *same* NotchShape as the fill and masks the top
                // strip away, rather than tracing a separately-built outline.
                // Now that the fill uses continuous corners, a hand-built
                // circular-arc outline would sit a pixel or two off it around
                // the bottom curves — exactly where a hairline is most visible.
                if state.isExpanded {
                    NotchShape(cornerRadius: radius)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                        .mask(alignment: .bottom) { Rectangle().padding(.top, 1) }
                }
            }
            // Deliberately no .shadow(): its gaussian tail reaches the window
            // boundary and clips into a visible block on bright wallpapers.
            // Edge definition comes from the hairline stroke and, when music
            // plays, the ambient line.
    }
}

/// "Ambient mode": a thin line of the artwork's dominant color hugging the
/// panel's silhouette (sides and bottom), with only a small soft bloom. Total
/// spread is under ~15pt — nowhere near the window boundary, so it can never
/// clip into a block.
private struct AmbientGlow: View {
    @ObservedObject var media: NowPlayingManager
    let radius: CGFloat
    let isExpanded: Bool

    var body: some View {
        if media.isPlaying, let accent = media.current.accent {
            ZStack {
                // Small soft bloom right at the edge.
                NotchEdgeShape(cornerRadius: radius)
                    .stroke(accent, lineWidth: 4)
                    .blur(radius: 5)
                    .opacity(isExpanded ? 0.5 : 0.35)
                // The line itself, hugging the silhouette.
                NotchEdgeShape(cornerRadius: radius)
                    .stroke(accent, lineWidth: 1.5)
                    .blur(radius: 0.5)
                    .opacity(isExpanded ? 0.95 : 0.7)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            // Keyed on the artwork token rather than the colour: the accent now
            // arrives a beat after the track metadata (it is derived off the
            // main thread), and keying on `accent` meant the very first frame
            // of a new track could paint the old colour with no animation
            // pending. The token changes exactly once per cover.
            .animation(Motion.accentShift, value: media.current.artworkToken)
        }
    }
}

/// The notch silhouette minus its top edge, for stroking. The top sits against
/// the screen edge right beside the notch cutout, where a light hairline would
/// give the cutout away.
struct NotchEdgeShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}

/// A rectangle whose bottom corners are rounded — the classic notch silhouette.
struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    /// Square at the top (it meets the screen edge beside the cutout), rounded
    /// at the bottom, with **continuous** corners.
    ///
    /// This used to build the bottom corners from `addArc` — quarter circles.
    /// The problem with a circular corner is that curvature jumps from zero
    /// along the straight edge to `1/r` the instant the arc begins, and the eye
    /// reads that discontinuity as a pinch where the two meet. A continuous
    /// corner ramps curvature in, which is what makes Apple's own rounded
    /// shapes — and the Dynamic Island — look poured rather than cut.
    ///
    /// `UnevenRoundedRectangle` gives the real system squircle rather than an
    /// approximation of it, and still animates, because `animatableData` above
    /// drives the radius it is built from.
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: r,
            bottomTrailingRadius: r,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)
    }
}

/// What shows on the collapsed strip: artwork on the left, the equalizer glyph
/// on the right, with the physical notch left clear between them.
private struct CollapsedContent: View {
    @ObservedObject var media: NowPlayingManager
    @ObservedObject var battery: BatteryMonitor
    /// Width of the hardware notch to keep clear in the middle (0 when the
    /// whole simulated strip is visible).
    let deadZone: CGFloat
    let showMediaGlyph: Bool
    let showBattery: Bool
    let morph: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                if showMediaGlyph, let art = media.current.artwork {
                    // Half of the matched pair — the other half is the 62pt
                    // artwork in MediaView. No `.transition` on the wrapper:
                    // the matched geometry owns its insert and removal, and a
                    // scale/opacity transition on top fights it.
                    ZStack {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                            .id(media.current.artworkToken)
                            .transition(.opacity)
                    }
                    .frame(width: Metrics.peekArtworkSize,
                           height: Metrics.peekArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.peekArtworkRadius,
                                                style: .continuous))
                    .animation(Motion.contentFade, value: media.current.artworkToken)
                    .matchedGeometryEffect(id: NotchRootView.artworkID, in: morph)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: deadZone)

            HStack(spacing: 5) {
                if showMediaGlyph {
                    WaveformGlyph(tint: media.current.accent ?? .white,
                                  isPlaying: media.isPlaying)
                        .transition(.scale.combined(with: .opacity))
                }
                // Battery hints only fit where the strip is fully visible.
                if showBattery, deadZone == 0 {
                    if battery.isCharging {
                        BatteryBolt()
                    } else if battery.isPresent && battery.level < 0.2 {
                        Image(systemName: "battery.25percent")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Charger-connected acknowledgement: a bolt in one wing, the charge level in
/// the other. Deliberately the same shape as the HUD readout — the notch has
/// one visual grammar for "here is a fact about your Mac, briefly".
private struct ChargingContent: View {
    @ObservedObject var battery: BatteryMonitor
    let deadZone: CGFloat

    @State private var arrived = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                // A single arrival beat rather than a loop: this is on screen
                // for two seconds, and something still pulsing when it vanishes
                // reads as unfinished.
                .scaleEffect(arrived || reduceMotion ? 1 : 0.4)
                .opacity(arrived || reduceMotion ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: deadZone)

            Text("\(Int((battery.level * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            guard !reduceMotion else { arrived = true; return }
            withAnimation(Motion.arrival) { arrived = true }
        }
    }
}

/// Volume / brightness readout: icon in one wing, level bar in the other, with
/// the physical notch kept clear between them.
private struct HUDContent: View {
    let hud: NotchHUD
    let deadZone: CGFloat

    private let barWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: hud.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: deadZone)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white.opacity(0.92))
                    .frame(width: max(3, barWidth * CGFloat(min(1, max(0, hud.level)))))
            }
            .frame(width: barWidth, height: 4)
            .animation(Motion.readout, value: hud.level)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The little equalizer from the website — a few bars that breathe while
/// something is playing. Tinted with the artwork's accent so it ties into the
/// ambient glow.
private struct WaveformGlyph: View {
    var tint: Color = .white
    /// Drives the bars. Paused music leaves them settled rather than dancing to
    /// nothing — the glyph used to loop forever regardless of playback, which
    /// made the notch look like it was playing when it wasn't.
    var isPlaying: Bool

    @State private var animating = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private let heights: [CGFloat] = [5, 11, 7, 9]
    private let restHeight: CGFloat = 3

    /// Bars only move when there is sound *and* the user hasn't asked for less
    /// motion. Under Reduce Motion they hold at their full heights instead of
    /// collapsing, so the glyph still reads as "audio" without moving.
    private var isDancing: Bool { isPlaying && animating && !reduceMotion }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: 2.5,
                           height: isDancing ? height
                                 : (reduceMotion && isPlaying ? height : restHeight))
                    .animation(
                        isDancing
                            ? Motion.equalizerBar
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.11)
                            // Settling on pause is a one-shot, not a loop —
                            // keeping repeatForever here would leave an
                            // animation running against a constant value.
                            : Motion.micro,
                        value: isDancing
                    )
            }
        }
        .frame(height: 12)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

/// Expanded panel: a slim header (clock, weather, battery, settings) over a
/// horizontal three-column body — media · calendar week · shelf.
private struct ExpandedContent: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    let morph: Namespace.ID

    /// Reading order, left to right. The header goes first because it is the
    /// top edge of the panel and anchors everything below it; the columns then
    /// cascade the way the eye already travels. Indices are assigned here
    /// rather than per-view so the order stays obvious in one place.
    /// (Reduce Motion is handled inside `NotchEntrance`, not here.)
    private enum Slot: Int { case header, media, calendar, shelf }

    var body: some View {
        VStack(spacing: 9) {
            HeaderRow(viewModel: viewModel)
                .notchEntrance(Slot.header.rawValue)

            HStack(alignment: .center, spacing: 14) {
                if settings.showMedia {
                    MediaView(media: viewModel.media, morph: morph)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .notchEntrance(Slot.media.rawValue)
                }
                if settings.showMedia && (settings.showCalendar || settings.showShelf) {
                    columnDivider.notchEntrance(Slot.media.rawValue)
                }
                if settings.showCalendar {
                    CalendarWeekStrip(calendar: viewModel.calendar)
                        .frame(maxWidth: .infinity)
                        .notchEntrance(Slot.calendar.rawValue)
                }
                if settings.showCalendar && settings.showShelf {
                    columnDivider.notchEntrance(Slot.calendar.rawValue)
                }
                if settings.showShelf {
                    TrayView(tray: viewModel.tray)
                        .frame(maxWidth: (settings.showMedia || settings.showCalendar) ? 150 : .infinity)
                        .notchEntrance(Slot.shelf.rawValue)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    private var columnDivider: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.14), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
    }
}

/// Slim top strip: live clock on the left; weather, battery, and a settings
/// gear on the right.
private struct HeaderRow: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 9) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                if settings.showWeather {
                    WeatherPill(weather: viewModel.weather)
                }
                if settings.showBattery {
                    BatteryView(battery: viewModel.battery)
                }
                Button { viewModel.onOpenSettings?() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .hoverLift(restOpacity: 0.55)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Settings")
            }
        }
    }
}

/// Small capsule with the current conditions; hidden until a snapshot arrives.
private struct WeatherPill: View {
    @ObservedObject var weather: WeatherProvider

    var body: some View {
        if let snapshot = weather.current {
            HStack(spacing: 5) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                Text(snapshot.temperatureText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
            .help(snapshot.summary)
            .transition(.blurReplace)
        }
    }
}

/// Horizontal week strip — month + a 7-day window centred on today (today
/// highlighted) — with the next event (or "Nothing for today") beneath it.
private struct CalendarWeekStrip: View {
    @ObservedObject var calendar: CalendarModel
    @ObservedObject private var settings = AppSettings.shared

    /// Today's highlight. Was a hardcoded blue; now follows the user's accent,
    /// which is the one place in the notch that tint applies — the ambient glow
    /// keeps following the artwork.
    private var accent: Color { settings.accent }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = context.date
            let cal = Calendar.current
            let days = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }

            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(today, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .fixedSize()
                    HStack(spacing: 3) {
                        ForEach(days, id: \.self) { day in
                            let isToday = cal.isDate(day, inSameDayAs: today)
                            VStack(spacing: 3) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(isToday ? accent : .white.opacity(0.3))
                                Text(day, format: .dateTime.day())
                                    .font(.system(size: 13, weight: isToday ? .bold : .regular, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isToday ? accent : .white.opacity(0.6))
                            }
                            .frame(width: 21)
                        }
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 9.5))
                    Text(subtitle).font(.system(size: 10)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.contentFade, value: calendar.upcoming)
        }
    }

    /// Line under the week strip. The dates stay useful even without calendar
    /// access, so the strip is never hidden — only this line changes, and it
    /// says where to fix it rather than just reporting that something is off.
    private var subtitle: String {
        if !calendar.isAuthorized { return "Allow Calendar in Settings → Access" }
        if let next = calendar.upcoming.first { return "\(next.timeText) · \(next.title)" }
        return "Nothing for today"
    }
}
