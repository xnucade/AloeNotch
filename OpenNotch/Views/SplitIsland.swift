import SwiftUI

/// The split island: a resident activity (a running timer) pinched off beside
/// the media peek as its own black bubble. See `PanelState.Peek.split`.
///
/// The pinch is drawn, not filtered. The textbook metaball — blur both shapes
/// together, then alpha-threshold the result back to a hard edge — costs a
/// full-surface blur every frame, which is the per-frame work that made the
/// old `.blurReplace` stutter. Instead the bridge between strip and bubble is
/// an explicit shape whose waist thins as the gap opens and vanishes below a
/// few points: the stretch, thin and snap of the goo, for the price of one
/// small path. It's only non-empty while the bubble is close enough to touch.
///
/// The bubble always exists behind the strip; out of a split it is tucked
/// fully under it (`gap == -width`) and transparent. Keeping it alive is what
/// lets the merge animate — a view removed on the state change would just
/// vanish.
struct SplitBubble: View, Animatable {
    /// From the strip's trailing edge to the bubble's leading edge. Negative
    /// while it overlaps the strip; `NotchMetrics.bubbleGap` at rest.
    var gap: CGFloat
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let activity: LiveActivity?
    let center: LiveActivityCenter
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var animatableData: CGFloat {
        get { gap }
        set { gap = newValue }
    }

    /// The gap at which the bridge's waist reaches zero. Just short of the
    /// resting gap, so the snap lands at the end of the travel and a bouncy
    /// arrival can't re-join them on the rebound.
    static let stretch = NotchMetrics.bubbleGap - 1.5
    /// Below this the bridge is gone: a hairline would read as a rendering
    /// fault, not as the last strand of something liquid.
    static let snapWaist: CGFloat = 2.5

    private var tucked: Bool { gap <= -width + 0.5 }

    /// Full height while the bubble overlaps, thinning to nothing as the gap
    /// opens to `stretch`.
    private var waist: CGFloat {
        height * (1 - min(1, max(0, gap / Self.stretch)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Its feet start a little past each body's rounded corner, so
            // the fillets cover the corners while the two are joined.
            LiquidBridge(waist: waist)
                .fill(.black)
                .frame(width: max(0, gap + radius * 2.4), height: height)
                .offset(x: -radius * 1.2)
            bubble
                .offset(x: gap)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .opacity(tucked ? 0 : 1)
        .allowsHitTesting(!tucked)
    }

    private var bubble: some View {
        NotchShape(cornerRadius: radius)
            .fill(.black)
            .overlay { content.opacity(contentOpacity) }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover(perform: onHover)
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity?.accessibilityText ?? "")
    }

    /// Fades in over the last stretch before the bubble clears the strip, so
    /// the readout never slides out from under the strip half-drawn.
    private var contentOpacity: Double {
        Double(min(1, max(0, (gap + width * 0.4) / (width * 0.4))))
    }

    @ViewBuilder
    private var content: some View {
        if let activity {
            HStack(spacing: Metrics.Spacing.tight) {
                Image(systemName: activity.symbol)
                    .font(Typography.icon(11))
                    .foregroundStyle(activity.tint)
                    .contentTransition(.symbolEffect(.replace))
                if width > NotchMetrics.bubbleWidth(.compact) {
                    ActivityTrailing(activity: activity, center: center)
                }
            }
            .padding(.horizontal, Metrics.Spacing.snug)
        }
    }
}

/// The liquid bridge: the full rect between strip and bubble, with a bell
/// cut up from the bottom. The bell's feet are flat — they continue the two
/// bottom edges, which is what makes the join read as a fillet rather than a
/// crack — and its apex sits `waist` below the top edge. As the waist thins
/// the strand retreats into the bezel, so it breaks at the screen's edge,
/// where both shapes hang from, rather than in mid-air.
private struct LiquidBridge: Shape {
    let waist: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width > 0, waist >= SplitBubble.snapWaist else { return p }
        let apex = CGPoint(x: rect.midX, y: rect.minY + waist)
        let half = rect.width / 2
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Horizontal tangents at the feet and at the apex.
        p.addCurve(to: apex,
                   control1: CGPoint(x: rect.maxX - half * 0.55, y: rect.maxY),
                   control2: CGPoint(x: apex.x + half * 0.35, y: apex.y))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                   control1: CGPoint(x: apex.x - half * 0.35, y: apex.y),
                   control2: CGPoint(x: rect.minX + half * 0.55, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
