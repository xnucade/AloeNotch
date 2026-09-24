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
    private var showMediaGlyph: Bool { state.showsMedia }

    /// The bubble keeps its last size while it merges back, so it doesn't
    /// change width on its way under the strip.
    @State private var lastBubble: PanelState.ActivitySize = .regular

    private var splitBubble: some View {
        let size = state.bubble ?? lastBubble
        let width = NotchMetrics.bubbleWidth(size)
        let split = state.bubble != nil
        let reduceMotion = a11y.reduceMotion
        // Reduce Motion: no travel, no bridge — it sits at rest and fades.
        let gap = split || reduceMotion ? NotchMetrics.bubbleGap : -width
        return SplitBubble(
            gap: gap,
            width: width,
            height: stripHeight,
            radius: Metrics.collapsedRadius,
            activity: viewModel.activities.resident,
            center: viewModel.activities,
            onHover: { viewModel.hoverChanged($0) },
            onTap: { viewModel.notchClicked() }
        )
        .opacity(reduceMotion && !split ? 0 : 1)
        .allowsHitTesting(split)
        .animation(Motion.resolve(Motion.detach, reduceMotion: reduceMotion), value: split)
        // Leading edge on the strip's trailing edge.
        .alignmentGuide(.trailing) { _ in 0 }
        .onChange(of: state.bubble) { _, new in if let new { lastBubble = new } }
    }

    /// The open panel's resting size, which its content is always laid out
    /// at — see the expanded branch in `notchSurface`.
    private var expandedSize: CGSize {
        metrics?.size(for: .expanded) ?? NotchGeometry.simulatedNotchSize
    }

    /// The surface's current on-screen size, straight from the one function
    /// that decides it (`NotchMetrics.size(for:)`).
    private var surfaceSize: CGSize {
        let base = reached(metrics?.size(for: state) ?? NotchGeometry.simulatedNotchSize)
        guard !state.isExpanded else { return base }
        // A two-finger pull stretches it down, following the fingers.
        let pulled = CGSize(width: base.width, height: base.height + viewModel.pull)
        // The swell while the pointer decides. Never while open — see
        // `NotchViewModel.isAnticipating`.
        guard viewModel.isAnticipating else { return pulled }
        return CGSize(width: pulled.width + Metrics.swell.width,
                      height: pulled.height + Metrics.swell.height)
    }

    /// How far the surface reaches toward a file dragged over it: a few
    /// points down, and a few sideways on the cursor's side only. The far
    /// edge holds still (see `reachOffset`), so the shape leans toward the
    /// file rather than growing at it, and never uncovers the notch.
    static let reachDown: CGFloat = 4
    static let reachSide: CGFloat = 8

    private func reached(_ size: CGSize) -> CGSize {
        guard let bias = viewModel.dragReach, !a11y.reduceMotion else { return size }
        return CGSize(width: size.width + Self.reachSide * abs(bias),
                      height: size.height + Self.reachDown)
    }

    /// Recentres the widened surface so only the cursor's side moved.
    private var reachOffset: CGFloat {
        guard let bias = viewModel.dragReach, !a11y.reduceMotion else { return 0 }
        return Self.reachSide * bias / 2
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

    private var shoulder: CGFloat {
        Metrics.shoulder(for: state, hardwareNotch: hasHardwareNotch)
    }

    private var notchSurface: some View {
        let radius = Metrics.radius(expanded: state.isExpanded)
        return ZStack {
            panelFill

            Group {
                if state.isExpanded {
                    Group {
                        if settings.panelLayout == .focused {
                            FocusedContent(viewModel: viewModel, morph: morph)
                        } else {
                            ExpandedContent(viewModel: viewModel, morph: morph)
                        }
                    }
                        .padding(.horizontal, Metrics.panelHorizontalInset)
                        // Clear the physical notch.
                        .padding(.top, stripHeight + Metrics.contentTopGap)
                        .padding(.bottom, Metrics.panelBottomInset)
                        // Laid out once, at the open size, whatever size the
                        // surface happens to be mid-spring. Fitted to the
                        // animating frame instead, every column rode the
                        // spring: the shape's leading edge overshoots left on
                        // a bouncy open, and the content slid in from the left
                        // and bounced with it. Now the shape reveals content
                        // that holds still, pinned to the top edge.
                        .frame(width: expandedSize.width, height: expandedSize.height)
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
                } else if case .peek(.activity) = state {
                    // Every transient announcement — volume, brightness,
                    // charging, a device connecting — draws through here.
                    // Keyed on the state rather than on the centre having
                    // something, so the content drawn always matches the width
                    // the state machine sized the strip for.
                    ActivityContent(
                        center: viewModel.activities,
                        deadZone: hasHardwareNotch ? (metrics?.notchSize.width ?? 0) : 0
                    )
                    .padding(.horizontal, hasHardwareNotch ? Metrics.hudInsetHardware
                                                           : Metrics.hudInsetSimulated)
                    .transition(.activityEntrance(reduceMotion: a11y.reduceMotion))
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
        .modifier(SurfaceFrame(size: surfaceSize))
        .offset(x: reachOffset)
        // Clip AFTER the frame so the clip bounds follow the animating size.
        // (Clipping the inner Group instead sized the clip to the *content*, so
        // collapsing left the outgoing panel ghosted at full width outside the
        // notch.) This also keeps inner light effects inside the panel.
        .clipShape(NotchShape(cornerRadius: radius, shoulder: shoulder))
        // Behind the strip, so it emerges from under it rather than on top.
        .background(alignment: .topTrailing) { splitBubble }
        // Glow lives outside the clip so its bloom can still extend past the edge.
        .background {
            if settings.ambientGlow {
                AmbientGlow(
                    media: viewModel.media,
                    radius: radius,
                    shoulder: shoulder,
                    isExpanded: state.isExpanded
                )
            }
        }
        // The one animation driving the whole surface: frame, corner radius,
        // the content branch transitions, and the matched artwork all move
        // under this. The curve comes from the view model, which picks it per
        // transition (bouncier opening, settled closing, quick between peeks).
        // A dropped file is swallowed: one small scale from the top edge.
        .scaleEffect(viewModel.gulping ? 0.98 : 1, anchor: .top)
        .animation(viewModel.stateAnimation, value: state)
        .animation(Motion.resolve(Motion.hud, reduceMotion: a11y.reduceMotion),
                   value: viewModel.dragReach)
        .animation(Motion.resolve(Motion.anticipate, reduceMotion: a11y.reduceMotion),
                   value: viewModel.isAnticipating)
        // 1:1 while the fingers move; a spring only on the way back.
        .animation(viewModel.pull == 0 ? Motion.resolve(Motion.hud, reduceMotion: a11y.reduceMotion) : nil,
                   value: viewModel.pull)
        .contentShape(Rectangle())
        .onHover { viewModel.hoverChanged($0) }
        // Only while closed, so it can never swallow a click meant for a
        // control inside the open panel.
        .gesture(TapGesture().onEnded { viewModel.notchClicked() },
                 including: state.isExpanded ? .none : .all)
        // VoiceOver can reach the notch but can't hover it: name it, and give
        // it the open/close the pointer would.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AloeNotch")
        .accessibilityAction(named: state.isExpanded ? "Close" : "Open") {
            state.isExpanded ? viewModel.dismiss() : viewModel.notchClicked()
        }
        // Dragging a file over the collapsed strip opens the shelf; dropping
        // directly on the strip stages it immediately.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            let accepted = viewModel.tray.handleDrop(providers)
            if accepted { Haptics.caught() }
            return accepted
        }
        .onChange(of: isDropTargeted) { _, targeted in
            viewModel.hoverChanged(targeted || state.isExpanded, immediate: targeted)
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
        return NotchShape(cornerRadius: radius, shoulder: shoulder)
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
                //
                // The stroke uses the shoulder-less outline and stops where
                // the shoulders begin: stroking the fill's path would also
                // outline the shoulder wedges' inner edges, a seam across the
                // flare.
                if state.isExpanded {
                    NotchShape(cornerRadius: radius)
                        .stroke(Ink.fill, lineWidth: 1)
                        .mask(alignment: .bottom) {
                            Rectangle().padding(.top, shoulder + 1)
                        }
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
    let shoulder: CGFloat
    let isExpanded: Bool

    var body: some View {
        if media.isPlaying, let accent = media.current.accent {
            ZStack {
                // Small soft bloom right at the edge.
                NotchEdgeShape(cornerRadius: radius, shoulder: shoulder)
                    .stroke(accent, lineWidth: 4)
                    .blur(radius: 5)
                    .opacity(isExpanded ? 0.5 : 0.35)
                // The line itself, hugging the silhouette.
                NotchEdgeShape(cornerRadius: radius, shoulder: shoulder)
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
    var shoulder: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, shoulder) }
        set { cornerRadius = newValue.first; shoulder = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        let s = NotchShape.clampedShoulder(shoulder, in: rect)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX + s, y: rect.minY))
        if s > 0 { NotchShape.addShoulderCurve(to: &p, in: rect, s: s, trailing: true) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        if s > 0 { NotchShape.addShoulderCurve(to: &p, in: rect, s: s, trailing: false, reversed: true) }
        return p
    }
}

/// A rectangle whose bottom corners are rounded — the classic notch silhouette.
struct NotchShape: Shape {
    var cornerRadius: CGFloat
    /// Concave flare at the top corners, drawn outside `rect`. See
    /// `Metrics.shoulder(for:hardwareNotch:)`.
    var shoulder: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, shoulder) }
        set { cornerRadius = newValue.first; shoulder = newValue.second }
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
    ///
    /// The shoulders are two separate wedges added to the same path, so one
    /// fill covers everything and there is no antialiasing seam between them.
    /// Each wedge overlaps the body by a point for the same reason.
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: r,
            bottomTrailingRadius: r,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)

        let s = Self.clampedShoulder(shoulder, in: rect)
        guard s > 0.5 else { return p }
        for trailing in [false, true] {
            let edge = trailing ? rect.maxX : rect.minX
            let inward: CGFloat = trailing ? -1 : 1
            // Both wedges must wind the same way as the body. They are
            // mirror images, so drawn with the same steps the trailing one
            // winds the other way, and under the non-zero rule its overlap
            // with the body cancels out into a hairline gap.
            var wedge = Path()
            wedge.move(to: CGPoint(x: edge + inward, y: rect.minY))
            if trailing {
                wedge.addLine(to: CGPoint(x: edge + s, y: rect.minY))
                Self.addShoulderCurve(to: &wedge, in: rect, s: s, trailing: true)
                wedge.addLine(to: CGPoint(x: edge + inward, y: rect.minY + s))
            } else {
                wedge.addLine(to: CGPoint(x: edge + inward, y: rect.minY + s))
                wedge.addLine(to: CGPoint(x: edge, y: rect.minY + s))
                Self.addShoulderCurve(to: &wedge, in: rect, s: s, trailing: false, reversed: true)
            }
            wedge.closeSubpath()
            p.addPath(wedge)
        }
        return p
    }

    /// A shoulder can't be taller than the strip it hangs from.
    static func clampedShoulder(_ shoulder: CGFloat, in rect: CGRect) -> CGFloat {
        max(0, min(shoulder, rect.height / 2))
    }

    /// Quarter-circle fillet between the screen edge and one side, bowing in
    /// toward the corner so it reads as concave. Forward runs from the screen
    /// edge down to the side; `reversed` runs back up.
    static func addShoulderCurve(to p: inout Path, in rect: CGRect, s: CGFloat,
                                 trailing: Bool, reversed: Bool = false) {
        let k: CGFloat = 0.5523   // cubic approximation of a quarter circle
        let edge = trailing ? rect.maxX : rect.minX
        let out: CGFloat = trailing ? 1 : -1
        let top = CGPoint(x: edge + out * s, y: rect.minY)
        let side = CGPoint(x: edge, y: rect.minY + s)
        let nearTop = CGPoint(x: edge + out * s * (1 - k), y: rect.minY)
        let nearSide = CGPoint(x: edge, y: rect.minY + s * (1 - k))
        if reversed {
            p.addCurve(to: top, control1: nearSide, control2: nearTop)
        } else {
            p.addCurve(to: side, control1: nearTop, control2: nearSide)
        }
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
                            .font(Typography.icon(11))
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Whatever the notch is announcing right now.
///
/// One view for every transient announcement, driven entirely by the
/// `LiveActivity` value. Volume, brightness, charging and device events used to
/// be separate views with separate layouts that happened to look alike; the
/// notch should have one visual grammar for "here is a fact about your Mac,
/// briefly", and this is it — a symbol on the left wing, a value on the right,
/// the hardware cutout kept clear between them.
private struct ActivityContent: View {
    @ObservedObject var center: LiveActivityCenter
    let deadZone: CGFloat

    @State private var arrived = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        if let activity = center.showing {
            HStack(spacing: 0) {
                HStack(spacing: Metrics.Spacing.tight) {
                    Image(systemName: activity.symbol)
                        .font(Typography.icon(13))
                        .foregroundStyle(activity.tint)
                        // Symbols swap in place when only the glyph changes —
                        // speaker.wave.1 to .wave.3 as the level climbs.
                        .contentTransition(.symbolEffect(.replace))
                    if let title = activity.title {
                        Text(title)
                            .font(Typography.micro(.semibold))
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                    }
                }
                // A single arrival beat rather than a loop: this is on screen
                // for a second or two, and something still moving when it
                // vanishes reads as unfinished.
                .scaleEffect(arrived || reduceMotion ? 1 : 0.4)
                .opacity(arrived || reduceMotion ? 1 : 0)
                // Resolves as it grows. The glyph group is ~40pt across, so
                // the blur is as cheap as blurs get.
                .blur(radius: arrived || reduceMotion ? 0 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: deadZone)

                ActivityTrailing(activity: activity, center: center)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // Keyed on kind, not id: a volume readout replacing a volume
            // readout should track, not restart its arrival beat. A *different*
            // kind arriving is genuinely new and gets the beat.
            .id(activity.kind)
            // One element, one sentence — "Volume, 60 percent" — instead of
            // a glyph, a title and an unlabeled bar read separately.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityText)
            .onAppear {
                guard !reduceMotion else { arrived = true; return }
                arrived = false
                withAnimation(Motion.arrival) { arrived = true }
            }
        }
    }
}

/// The surface's frame, laid out afresh on every frame of its animation.
///
/// A plain `.frame` animates by interpolating where each view ends up
/// *relative to its parent*, and the surface's parent centres it — so the
/// surface's leading edge travels, overshooting on a bouncy open, and
/// everything positioned from that edge travels with it. That was the open
/// panel's content sliding in from the left and bouncing. As an `Animatable`
/// modifier the frame is re-laid-out with each interpolated size instead, so
/// the fixed-size open content is re-centred every frame and holds still on
/// screen while the shape grows around it.
///
/// Top-aligned: the open content hangs from the top edge while the frame is
/// still smaller than it.
private struct SurfaceFrame: ViewModifier, Animatable {
    var size: CGSize

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func body(content: Content) -> some View {
        content.frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// What an activity shows beside its symbol: a level bar, a short value or a
/// live countdown. Its own view so the split island's bubble draws exactly
/// what the full strip would.
struct ActivityTrailing: View {
    let activity: LiveActivity
    @ObservedObject var center: LiveActivityCenter
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        switch activity.trailing {
        case .none:
            EmptyView()
        case .level(let value):
            // The track takes the same hue as the fill so a tinted readout
            // reads as one object rather than a coloured bar in a grey slot.
            ZStack(alignment: .leading) {
                Capsule().fill(activity.tint.opacity(0.18))
                Capsule().fill(activity.tint.opacity(0.92))
                    .frame(width: max(3, 62 * CGFloat(min(1, max(0, value)))))
            }
            .frame(width: 62, height: 4)
            .animation(Motion.readout, value: value)
            .modifier(RubberBand(push: center.limitPush, reduceMotion: reduceMotion))
        case .text(let value):
            Text(value)
                .font(Typography.body(.semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
                .animation(Motion.readout, value: value)
                .lineLimit(1)
        case .countdown(let deadline):
            // A quarter-second timeline rather than SwiftUI's own
            // `Text(timerInterval:)`, which always renders to the second: at
            // 0.25s the digit flips within a frame or two of the real second
            // boundary, so a glance at the notch and a glance at a wall clock
            // agree.
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(CountdownState.clock(deadline.timeIntervalSince(context.date)))
                    .font(Typography.body(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.readout,
                               value: Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                    .lineLimit(1)
            }
        }
    }
}

/// Stretch against the stop. The bar lengthens toward the end it was pushed
/// at and thins as it does (squash and stretch keeps its area roughly
/// constant, which is what makes it read as elastic rather than as growing),
/// then springs back. Anchored at the *opposite* end, so the stretch goes
/// where the push went.
private struct RubberBand: ViewModifier {
    let push: LiveActivityCenter.LimitPush
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: CGFloat(1), trigger: push) { bar, stretch in
                bar.scaleEffect(x: stretch, y: 1 - (stretch - 1) * 2.5,
                                anchor: push.direction > 0 ? .leading : .trailing)
            } keyframes: { _ in
                SpringKeyframe(1.1, duration: 0.09, spring: .snappy)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy(extraBounce: 0.1))
            }
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

    /// The third column exists if either of the things it holds is enabled.
    private var hasUtilities: Bool {
        settings.showShelf || settings.showClipboard || settings.showTimer
    }

    var body: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            HeaderRow(viewModel: viewModel)
                .notchEntrance(Slot.header.rawValue)

            HStack(alignment: .center, spacing: Metrics.Spacing.loose) {
                if settings.showMedia {
                    MediaView(media: viewModel.media, morph: morph)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .notchEntrance(Slot.media.rawValue)
                }
                if settings.showMedia && (settings.showCalendar || hasUtilities) {
                    columnDivider.notchEntrance(Slot.media.rawValue)
                }
                if settings.showCalendar {
                    CalendarWeekStrip(calendar: viewModel.calendar)
                        .frame(maxWidth: .infinity)
                        .notchEntrance(Slot.calendar.rawValue)
                }
                if settings.showCalendar && hasUtilities {
                    columnDivider.notchEntrance(Slot.calendar.rawValue)
                }
                if hasUtilities {
                    UtilityColumn(tray: viewModel.tray,
                                  clipboard: viewModel.clipboard,
                                  timer: viewModel.timer)
                        .frame(maxWidth: (settings.showMedia || settings.showCalendar) ? 160 : .infinity)
                        .notchEntrance(Slot.shelf.rawValue)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    private var columnDivider: some View {
        LinearGradient(colors: [.clear, Ink.fillStrong, .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
    }
}

/// Slim top strip: live clock on the left; weather, battery, and a settings
/// gear on the right. Shared by both panel layouts — it is the one part that
/// does not change between them.
struct HeaderRow: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared

    /// The header doubles as two pickers. Opening either swaps the row rather
    /// than dropping a menu or a popover: both open *outside* the panel, which
    /// takes the pointer out of the hover region and collapses the very thing
    /// they belong to.
    ///
    /// One mode rather than a boolean each, so the two can never both be open.
    @State private var mode: Mode = .clock

    enum Mode { case clock, output, forecast }

    var body: some View {
        Group {
            switch mode {
            case .clock:
                clockRow.transition(.opacity)
            case .output:
                AudioOutputRow(audio: viewModel.audioOutput) { close() }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .forecast:
                WeatherForecastRow(weather: viewModel.weather) { close() }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        // Anything that closes the panel has to reset the header, or reopening
        // it lands on a forecast the user left open ten minutes ago.
        .onChange(of: viewModel.panelState.isExpanded) { _, expanded in
            if !expanded { mode = .clock }
        }
    }

    private func close() {
        withAnimation(Motion.contentFade) { mode = .clock }
    }

    private var clockRow: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: Metrics.Spacing.regular) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(Typography.clock())
                    .monospacedDigit()
                    // `.contentTransition(.numericText())` was already here but
                    // never did anything: it describes *how* a change should be
                    // drawn, and something still has to declare that the change
                    // is animated at all. TimelineView just hands down a new
                    // date each minute, so the digits swapped instantly.
                    //
                    // Keyed on the minute rather than the date: the timeline
                    // republishes more often than the displayed value changes,
                    // and animating on every tick would restart the roll
                    // against an identical string.
                    .contentTransition(.numericText())
                    .animation(Motion.contentFade,
                               value: Calendar.current.component(.minute, from: context.date))
                    .foregroundStyle(Ink.primary)

                Spacer()

                if settings.showWeather {
                    WeatherPill(weather: viewModel.weather) {
                        withAnimation(Motion.contentFade) { mode = .forecast }
                    }
                }
                if settings.showBattery {
                    BatteryView(battery: viewModel.battery)
                }
                // Only when there is somewhere else for the sound to go. With
                // one output device the control would be a button that does
                // nothing, which is worse than no button.
                if viewModel.audioOutput.devices.count > 1 {
                    Button {
                        withAnimation(Motion.contentFade) { mode = .output }
                    } label: {
                        Image(systemName: viewModel.audioOutput.current?.symbol ?? "speaker.wave.2")
                            .font(Typography.icon(12, .medium))
                            .foregroundStyle(.white)
                            .hoverLift(restOpacity: 0.55)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Sound output: \(viewModel.audioOutput.current?.name ?? "unknown")")
                    .accessibilityLabel("Sound output")
                    .accessibilityValue(viewModel.audioOutput.current?.name ?? "")
                }
                CaffeineButton(caffeine: viewModel.caffeine, accent: settings.accent)

                Button { viewModel.onOpenSettings?() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(Typography.icon(12, .medium))
                        .foregroundStyle(.white)
                        .hoverLift(restOpacity: 0.55)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
    }
}

/// Keep-awake, as one glyph. Lit in the accent colour while it is holding the
/// Mac open, because a switch whose only state is "the icon looks slightly
/// different" is a switch people leave on by accident.
private struct CaffeineButton: View {
    @ObservedObject var caffeine: CaffeineController
    let accent: Color

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button { caffeine.toggle() } label: {
            Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(Typography.icon(12, .medium))
                .foregroundStyle(caffeine.isActive ? accent : (hovering ? .white : Ink.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(reduceMotion ? 1 : (hovering ? 1.12 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .help(caffeine.isActive ? "Let this Mac sleep again" : "Keep this Mac awake")
        .accessibilityLabel("Keep awake")
        .accessibilityValue(caffeine.isActive ? "On" : "Off")
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

/// The header, while the output picker is open: every output device as a chip.
///
/// Chips rather than a list because the header is 680pt of unused horizontal
/// space and a Mac rarely has more than four outputs — a vertical list would
/// need somewhere to live, and the only room is on top of the content the user
/// opened the panel to see.
private struct AudioOutputRow: View {
    @ObservedObject var audio: AudioOutputController
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: "speaker.wave.2")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(Ink.tertiary)

            // Scrolls rather than truncating: an aggregate device or a Mac with
            // several displays attached can list more than fits, and a chip cut
            // in half is unidentifiable.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.Spacing.tight) {
                    ForEach(audio.devices) { device in
                        AudioDeviceChip(device: device,
                                        isActive: device.id == audio.currentID) {
                            audio.select(device)
                            onClose()
                        }
                    }
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Typography.icon(11, .medium))
                    .foregroundStyle(.white)
                    .hoverLift(restOpacity: 0.5)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Close")
        }
        .onAppear { audio.refresh() }
    }
}

private struct AudioDeviceChip: View {
    let device: AudioOutputController.Device
    let isActive: Bool
    let action: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: device.symbol)
                    .font(Typography.icon(11, .medium))
                Text(device.name)
                    .font(Typography.micro(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? settings.accent : (hovering ? .white : Ink.secondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(isActive
                               ? settings.accent.opacity(0.18)
                               : (hovering ? Ink.fillStrong : Ink.fill))
            }
            .fixedSize()
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .help(isActive ? "\(device.name) — currently playing here" : "Send sound to \(device.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

/// Small capsule with the current conditions; hidden until a snapshot arrives.
///
/// Clickable only when a forecast actually came back. A temperature on its own
/// provokes exactly one question — do I need a jacket, is it going to rain —
/// and answering it is the only reason to make a readout a target. When the
/// forecast is missing the pill stays a readout rather than becoming a button
/// that opens an empty row.
private struct WeatherPill: View {
    @ObservedObject var weather: WeatherProvider
    let onOpenForecast: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        if let snapshot = weather.current {
            let interactive = !snapshot.hourly.isEmpty
            Button(action: onOpenForecast) {
                HStack(spacing: 5) {
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(Typography.icon(12, .medium))
                    Text(snapshot.temperatureText)
                        .font(Typography.body(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(hovering && interactive ? Ink.fillStrong : Ink.fill, in: Capsule())
                .contentShape(.capsule)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!interactive)
            .help(interactive ? "\(snapshot.summary) — see the next few hours" : snapshot.summary)
            .onHover { inside in
                withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                    hovering = inside
                }
            }
            .transition(.blurReplace)
        }
    }
}

/// The header, while the forecast is open: the next few hours as columns.
private struct WeatherForecastRow: View {
    @ObservedObject var weather: WeatherProvider
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Spacing.regular) {
            if let snapshot = weather.current {
                HStack(spacing: 5) {
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(Typography.icon(12, .medium))
                    Text(snapshot.summary)
                        .font(Typography.micro(.semibold))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Spacer(minLength: Metrics.Spacing.tight)

                HStack(spacing: Metrics.Spacing.regular) {
                    ForEach(snapshot.hourly) { hour in
                        VStack(spacing: 2) {
                            Text(hour.hourText)
                                .font(Typography.micro())
                                .foregroundStyle(Ink.tertiary)
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(Typography.icon(11, .medium))
                            Text(hour.temperatureText)
                                .font(Typography.micro(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Ink.primary)
                        }
                        .fixedSize()
                    }
                }
            }

            Spacer(minLength: Metrics.Spacing.tight)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Typography.icon(11, .medium))
                    .foregroundStyle(.white)
                    .hoverLift(restOpacity: 0.5)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Close")
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

            VStack(spacing: Metrics.Spacing.snug) {
                HStack(alignment: .center, spacing: Metrics.Spacing.regular) {
                    Text(today, format: .dateTime.month(.abbreviated))
                        .font(Typography.display())
                        .fixedSize()
                    HStack(spacing: 3) {
                        ForEach(days, id: \.self) { day in
                            let isToday = cal.isDate(day, inSameDayAs: today)
                            VStack(spacing: Metrics.Spacing.tight) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(Typography.micro(.semibold))
                                    .foregroundStyle(isToday ? accent : Ink.quaternary)
                                Text(day, format: .dateTime.day())
                                    .font(Typography.body(isToday ? .bold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(isToday ? accent : Ink.secondary)
                            }
                            .frame(width: 21)
                            // "T 24" read aloud is noise; say the day.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
                            .accessibilityAddTraits(isToday ? .isSelected : [])
                        }
                    }
                }

                if let meeting = joinable(at: today), let link = meeting.meeting {
                    // A call about to start outranks whatever is first in the
                    // list (usually an all-day event), and gets a way in.
                    HStack(spacing: Metrics.Spacing.tight) {
                        Text("\(meeting.timeText) · \(meeting.title)")
                            .font(Typography.caption())
                            .lineLimit(1)
                            .foregroundStyle(Ink.secondary)
                        JoinMeetingButton(link: link)
                    }
                } else {
                    HStack(spacing: Metrics.Spacing.tight) {
                        Image(systemName: "calendar").font(Typography.icon(11, .medium))
                        Text(subtitle).font(Typography.caption()).lineLimit(1)
                    }
                    .foregroundStyle(Ink.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.contentFade, value: calendar.upcoming)
        }
    }

    /// Line under the week strip. The dates stay useful even without calendar
    /// access, so the strip is never hidden — only this line changes, and it
    /// says where to fix it rather than just reporting that something is off.
    private func joinable(at now: Date) -> UpcomingEvent? {
        guard calendar.isAuthorized else { return nil }
        return calendar.upcoming.first { $0.isJoinable(at: now) }
    }

    private var subtitle: String {
        if !calendar.isAuthorized { return "Allow Calendar in Settings → Access" }
        if let next = calendar.upcoming.first { return "\(next.timeText) · \(next.title)" }
        return "Nothing for today"
    }
}
