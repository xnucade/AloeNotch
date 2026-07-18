import SwiftUI

struct MediaView: View {
    @ObservedObject var media: NowPlayingManager

    var body: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                if media.isAvailable && media.current.hasContent {
                    Text(media.current.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(media.current.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    controls
                } else {
                    Text(media.isAvailable ? "Nothing playing" : "Now Playing unavailable")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    if !media.isAvailable {
                        Text("Not supported on this macOS version")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: media.current)
    }

    private var artwork: some View {
        Group {
            if let art = media.current.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Ambient glow: the artwork itself, enlarged and blurred, casts its
        // colors onto the black panel the way the Dynamic Island does.
        .background {
            if let art = media.current.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .scaleEffect(1.35)
                    .blur(radius: 22)
                    .opacity(0.55)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            TransportButton(symbol: "backward.fill") { media.previous() }
            TransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                media.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            TransportButton(symbol: "forward.fill") { media.next() }
        }
        .padding(.top, 4)
    }
}

/// Plain transport button that brightens and scales slightly on hover, with a
/// press-down squish — the small physical touches Apple's own controls have.
private struct TransportButton: View {
    let symbol: String
    var size: CGFloat = 13
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 30, height: 30)
                .background(.white.opacity(hovering ? 0.12 : 0), in: Circle())
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(.snappy(duration: 0.2)) { hovering = inside }
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
