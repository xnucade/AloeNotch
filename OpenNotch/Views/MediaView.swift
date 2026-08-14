import SwiftUI

struct MediaView: View {
    @ObservedObject var media: NowPlayingManager
    /// Namespace for the matched artwork pair, owned by NotchRootView.
    let morph: Namespace.ID

    var body: some View {
        HStack(spacing: Metrics.Spacing.loose) {
            artwork
            VStack(alignment: .leading, spacing: Metrics.Spacing.hairline) {
                if media.isAvailable && media.current.hasContent {
                    Text(media.current.title)
                        .font(Typography.title())
                        .lineLimit(1)
                    Text(media.current.artist)
                        .font(Typography.caption())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    if media.current.duration > 0 {
                        ProgressScrubber(media: media).padding(.top, 3)
                    }
                    controls
                } else {
                    Text(media.isAvailable ? "Nothing playing" : "Now Playing unavailable")
                        .font(Typography.caption(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    if media.isAvailable {
                        Text("Start something in Music, Spotify or a browser.")
                            .font(Typography.micro(.regular))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Was "Not supported on this macOS version", which is
                        // no longer a possible cause — the minimum is macOS 26
                        // and the adapter covers every version from here on.
                        // If this shows now, the media helper failed to start,
                        // and the reason is in Console under "AloeNotch".
                        Text("The media helper didn't start. Relaunching AloeNotch usually fixes it.")
                            .font(Typography.micro(.regular))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Motion.contentFade, value: media.current)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let art = media.current.artwork {
                    // Half of the matched pair — the other half is the 15pt
                    // artwork in the peek strip (NotchRootView.CollapsedContent).
                    // SwiftUI interpolates the frame between the two, so the
                    // artwork travels out of the notch and grows.
                    //
                    // The ZStack is what carries the matched geometry, and it
                    // deliberately has no `.id`: the image inside changes
                    // identity on every track so it can crossfade, and if that
                    // identity change reached the matched-geometry view the
                    // morph would be re-registering mid-flight.
                    ZStack {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                            .id(media.current.artworkToken)
                            .transition(.opacity)
                    }
                    .frame(width: Metrics.expandedArtworkSize,
                           height: Metrics.expandedArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.expandedArtworkRadius,
                                                style: .continuous))
                    .animation(Motion.contentFade, value: media.current.artworkToken)
                    .matchedGeometryEffect(id: NotchRootView.artworkID, in: morph)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.expandedArtworkRadius, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)))
                        .frame(width: Metrics.expandedArtworkSize,
                               height: Metrics.expandedArtworkSize)
                }
            }
            .frame(width: Metrics.expandedArtworkSize, height: Metrics.expandedArtworkSize)
            // Ambient glow: the artwork itself, enlarged and blurred, casts its
            // colors onto the black panel the way the Dynamic Island does.
            .background {
                if let art = media.current.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .scaleEffect(1.35)
                        .blur(radius: 22)
                        .opacity(0.55)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            // Small badge of the source app (Music, Spotify, browser…).
            if let icon = media.current.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.black.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: -5, y: 5)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Metrics.Spacing.tight) {
            TransportButton(symbol: "backward.fill") { media.previous() }
            TransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                media.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            TransportButton(symbol: "forward.fill") { media.next() }
        }
        .padding(.top, 1)
    }
}

/// Plain transport button that brightens and scales slightly on hover, with a
/// press-down squish — the small physical touches Apple's own controls have.
private struct TransportButton: View {
    let symbol: String
    var size: CGFloat = 13
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 27, height: 27)
                .background(.white.opacity(hovering ? 0.12 : 0), in: Circle())
                // The lift is travel, so Reduce Motion drops it and lets the
                // brightness and fill changes carry the hover on their own.
                .scaleEffect(reduceMotion ? 1 : (hovering ? 1.08 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

/// Slim progress bar that advances live and can be dragged to seek. The
/// elapsed value is interpolated by the manager between source updates.
private struct ProgressScrubber: View {
    @ObservedObject var media: NowPlayingManager
    @State private var dragging = false
    @State private var dragFraction: Double = 0
    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        // Repaint twice a second so the fill creeps forward between updates.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = media.current.duration
            let elapsed = dragging ? dragFraction * duration : media.liveElapsed()
            let fraction = duration > 0 ? min(1, max(0, elapsed / duration)) : 0

            VStack(spacing: 2) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: max(2, w * fraction))
                        // The knob appears on hover as well as during a drag,
                        // so the bar advertises that it can be scrubbed before
                        // you commit to grabbing it.
                        Circle().fill(.white)
                            .frame(width: knobSize, height: knobSize)
                            .offset(x: min(w - knobSize / 2,
                                           max(-knobSize / 2, w * fraction - knobSize / 2)))
                    }
                    // Thickens under the cursor, the way system sliders do.
                    .frame(height: hovering || dragging ? 5 : 3)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                            hovering = inside
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                dragging = true
                                dragFraction = min(1, max(0, g.location.x / max(1, w)))
                            }
                            .onEnded { _ in
                                media.seek(to: dragFraction * duration)
                                dragging = false
                            }
                    )
                }
                .frame(height: 9)
                // Linear, and pinned to the TimelineView's 0.5s tick above rather
                // than to a Motion token: this is interpolation between two
                // samples of a real value, not an expressive curve. Easing it
                // would make playback appear to speed up and slow down.
                .animation(.linear(duration: dragging ? 0 : 0.5), value: fraction)

                HStack {
                    Text(timeString(elapsed))
                    Spacer()
                    Text(timeString(duration))
                }
                .font(Typography.micro(.regular))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// Grows on hover, grows further while actually dragging.
    private var knobSize: CGFloat {
        dragging ? 9 : (hovering ? 7 : 0)
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
