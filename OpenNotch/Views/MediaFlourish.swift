import SwiftUI

// The pieces that let the open panel take its light from what's playing:
// a wash of the cover's colour, a cover that leans under the pointer, and
// the small answers controls give when touched. Shared by every layout.

// MARK: - Light from the cover

/// The cover's colour, spilled across the open panel.
///
/// Two radial gradients rather than a blurred copy of the artwork: a blur
/// that wide is an offscreen pass every frame of the opening spring, and a
/// gradient is nearly free. The main pool sits under the artwork; a fainter
/// one in a neighbouring hue answers from the far corner, which is what keeps
/// a single-colour cover from reading as a flat tint.
///
/// Nothing reaches the top of the panel. The fill there has to stay pure
/// black for the notch to pass as hardware, so the wash is masked off below
/// the strip, and it is laid out at the open size and only faded: it can't
/// ride the opening spring up into the strip either.
struct PanelAurora: View {
    @ObservedObject var media: NowPlayingManager
    /// The strip's height: everything above it stays black.
    let clearTop: CGFloat
    let isExpanded: Bool

    private var accent: Color? {
        media.current.hasContent ? media.current.accent : nil
    }

    var body: some View {
        GeometryReader { geo in
            let reach = geo.size.width
            ZStack {
                if let accent {
                    ZStack {
                        // Falls off fast near the cover and slowly after, like
                        // light rather than a tint: bright where it lands,
                        // a long faint tail.
                        RadialGradient(
                            stops: [.init(color: accent.opacity(0.42), location: 0),
                                    .init(color: accent.opacity(0.17), location: 0.36),
                                    .init(color: accent.opacity(0.05), location: 0.72),
                                    .init(color: accent.opacity(0), location: 1)],
                            center: UnitPoint(x: 0.08, y: 0.86),
                            startRadius: 0, endRadius: reach * 0.64)
                        let answer = accent.hueShifted(by: -0.1)
                        RadialGradient(
                            colors: [answer.opacity(0.15), answer.opacity(0)],
                            center: UnitPoint(x: 1.0, y: 1.05),
                            startRadius: 0, endRadius: reach * 0.4)
                    }
                    .transition(.opacity)
                }
            }
            // The token, not the colour: see `AmbientGlow`.
            .animation(Motion.accentShift, value: media.current.artworkToken)
            .animation(Motion.accentShift, value: accent == nil)
        }
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: clearTop)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                Color.black
            }
        }
        // Paused, the light dims with the music instead of going out.
        .opacity(isExpanded ? (media.isPlaying ? 1 : 0.55) : 0)
        .animation(Motion.contentFade, value: media.isPlaying)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// The same colour, moved round the wheel by a fraction of a turn.
    /// Computed rather than drawn with `.hueRotation`, which is a filter and
    /// would cost the wash an offscreen pass.
    func hueShifted(by turn: Double) -> Color {
        guard let c = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue = c.hueComponent + turn
        hue -= hue.rounded(.down)
        return Color(hue: hue, saturation: c.saturationComponent, brightness: c.brightnessComponent)
    }
}

// MARK: - A cover you can feel

/// Cover art that leans toward the pointer and catches a little light where
/// it is, the way a physical sleeve would if you tipped it.
///
/// Travel, so Reduce Motion drops the lean and the lift; the highlight alone
/// still says the pointer is over it.
struct ArtworkTilt: ViewModifier {
    let radius: CGFloat
    /// Degrees at the edge. Small: past about ten the cover reads as a
    /// control being pressed rather than an object being looked at.
    var maxAngle: Double = 8

    @Environment(\.notchReduceMotion) private var reduceMotion
    /// Where the pointer is, −1…1 on each axis from the cover's centre.
    @State private var lean: CGPoint?
    /// The cover's side, measured, so the modifier needs no fixed size.
    @State private var side: CGFloat = 1

    private var angleX: Double { reduceMotion ? 0 : Double(lean?.y ?? 0) * -maxAngle }
    private var angleY: Double { reduceMotion ? 0 : Double(lean?.x ?? 0) * maxAngle }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    RadialGradient(
                        colors: [Ink.fillStrong, Ink.fill.opacity(0)],
                        center: UnitPoint(x: 0.5 + (lean?.x ?? 0) * 0.45,
                                          y: 0.5 + (lean?.y ?? 0) * 0.45),
                        startRadius: 0, endRadius: geo.size.width * 0.75)
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .opacity(lean == nil ? 0 : 1)
                }
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(angleX), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(angleY), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(lean != nil && !reduceMotion ? 1.03 : 1)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let next = CGPoint(x: clamp(point.x / max(1, side) * 2 - 1),
                                       y: clamp(point.y / max(1, side) * 2 - 1))
                    withAnimation(Motion.tilt) { lean = next }
                case .ended:
                    withAnimation(Motion.tiltRelease) { lean = nil }
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { side = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in side = new }
                }
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(1, max(-1, value)) }
}

extension View {
    /// See `ArtworkTilt`.
    func artworkTilt(radius: CGFloat) -> some View {
        modifier(ArtworkTilt(radius: radius))
    }
}

// MARK: - Buttons that answer

/// A glyph that darts sideways when its button is used and springs back:
/// previous leans left, next leans right. `direction` 0 does nothing, so
/// play and pause can share the button that carries this.
struct SkipNudge: ViewModifier {
    let direction: CGFloat
    /// Counts taps; the animator runs once per change.
    let taps: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: taps) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            CubicKeyframe(direction * Motion.nudgeTravel, duration: Motion.nudgeOut)
            SpringKeyframe(0, spring: Motion.nudgeHome)
        }
    }
}

// MARK: - Scrubber fill

enum MediaTint {
    /// The played part of a scrubber: the cover's colour at the start,
    /// running to white at the playhead, so the bar belongs to the song
    /// without losing the bright tip that marks where you are.
    static func scrubber(_ accent: Color?) -> LinearGradient {
        let lead = accent.map { $0.mix(with: .white, by: 0.25) } ?? Ink.primary
        return LinearGradient(colors: [lead, Ink.primary], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Today

private struct TodayChip: ViewModifier {
    let isToday: Bool
    let accent: Color
    let side: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: side, height: side)
            .background {
                if isToday { Circle().fill(accent) }
            }
    }
}

extension View {
    /// Today's date on a disc of the accent colour, the way a wall calendar
    /// gets a ring drawn round it: found at a glance, and not by colour alone.
    func todayChip(_ isToday: Bool, accent: Color, side: CGFloat) -> some View {
        modifier(TodayChip(isToday: isToday, accent: accent, side: side))
    }
}
