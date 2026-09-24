import SwiftUI

/// A one-line title that shows the rest of itself on hover.
///
/// Truncated titles scroll once per hover: a 1 s pause so the eye lands on
/// the start, a constant-speed crawl to the end, another second there, then a
/// quick return. Fitting titles never move, and nothing moves unhovered — a
/// ticker that runs by itself is the notch fidgeting in the corner of your
/// eye. Edges fade rather than clip while it moves, and Reduce Motion leaves
/// the ellipsis and the tooltip.
///
/// At rest this is an ordinary truncating `Text`. The scrolling copy exists
/// only while it moves, so a panel full of fitting titles pays for one
/// measurement each and nothing more.
struct MarqueeText: View {
    let text: String
    let font: Font

    @Environment(\.notchReduceMotion) private var reduceMotion
    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var leadFade: CGFloat = 0
    @State private var scrolling = false
    @State private var run: Task<Void, Never>?

    static let pause: Duration = .seconds(1)
    /// Points per second. Slow enough to read while it moves.
    static let speed: CGFloat = 30
    static let fade: CGFloat = 12

    private var overflow: CGFloat { max(0, fullWidth - boxWidth) }
    private var truncated: Bool { overflow > 0.5 }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(scrolling ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                // The width the title would like, measured off-layout.
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .leading) {
                if scrolling {
                    Text(text)
                        .font(font)
                        .fixedSize()
                        .offset(x: offset)
                        .frame(width: boxWidth, alignment: .leading)
                        .mask(edgeMask)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in inside ? start() : stop() }
            .help(truncated ? text : "")
    }

    private var edgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: leadFade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }

    private func start() {
        guard truncated, !reduceMotion, run == nil else { return }
        run = Task { @MainActor in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            // Far enough that the last glyph clears the trailing fade.
            let travel = overflow + Self.fade
            let duration = max(1.2, Double(travel / Self.speed))
            scrolling = true
            withAnimation(.easeOut(duration: 0.25)) { leadFade = Self.fade }
            withAnimation(.linear(duration: duration)) { offset = -travel }
            try? await Task.sleep(for: .seconds(duration) + Self.pause)
            guard !Task.isCancelled else { return }
            settle()
            // `run` stays set until the pointer leaves: once per hover.
        }
    }

    private func stop() {
        run?.cancel()
        run = nil
        settle()
    }

    /// Back to the start, then hand over to the truncating text.
    private func settle() {
        guard scrolling else { return }
        withAnimation(Motion.contentFade) {
            offset = 0
            leadFade = 0
        } completion: {
            if offset == 0 { scrolling = false }
        }
    }
}
