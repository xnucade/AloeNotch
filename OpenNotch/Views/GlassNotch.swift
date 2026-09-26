import SwiftUI
import AppKit

/// How the open panel is filled. Solid is the black that disappears into the
/// camera cutout; Glass lets the desktop through below it.
enum NotchStyle: String, CaseIterable, Identifiable {
    case solid, glass
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .glass: "Glass"
        }
    }

    var detail: String {
        switch self {
        case .solid: "Black, like the notch it grows out of."
        case .glass: "The open panel frosts the desktop behind it and picks up a colour-shifting edge. It stays black where it meets the camera, and whenever it's closed."
        }
    }
}

private struct NotchGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the open panel is drawn as glass, for the few elements
    /// that dress differently on it (a rim on a pill, a glow on a bar).
    var notchGlass: Bool {
        get { self[NotchGlassKey.self] }
        set { self[NotchGlassKey.self] = newValue }
    }
}

/// The open panel's glass: the desktop frosted and darkened, with solid black
/// across the top so the camera cutout stays invisible.
///
/// Where the panel meets the top of the screen it has to stay pure black —
/// the hardware notch is black, and anything lighter beside it outlines the
/// camera housing. So the frost starts below the notch and fades up into the
/// black, which reads as the glass growing out of the notch.
struct GlassPanelFill: View {
    /// Height of the band that stays solid black (the notch's own height).
    let solidTop: CGFloat
    var material: NSVisualEffectView.Material

    /// Darkens the frost toward the mockup's smoked glass. Enough that white
    /// text holds up over a bright wallpaper; not so much that it's black.
    private static let tint = 0.42
    /// How far the black takes to give way to glass below the notch.
    private static let fade: CGFloat = 34

    var body: some View {
        ZStack {
            FrostBackdrop(material: material, dark: true)
            Color.black.opacity(Self.tint)
            VStack(spacing: 0) {
                Color.black.frame(height: solidTop)
                LinearGradient(colors: [.black, .black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A thin colour-shifting edge for the glass panel, drawn inside the clip.
///
/// Colours come from the artwork when music plays, so the rim belongs to the
/// song; otherwise a cool default. While music plays the colours drift slowly
/// round the edge. The rim fades out toward the top so nothing light sits
/// beside the camera cutout.
struct GlassRim: View {
    var radius: CGFloat
    var shoulder: CGFloat
    /// Where the rim is fully faded out, measured from the top.
    var clearTop: CGFloat
    var accent: Color?
    var drifting: Bool

    @State private var turned = false

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.5
            AngularGradient(colors: palette + [palette[0]], center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(turned ? 360 : 0))
                .frame(width: geo.size.width, height: geo.size.height)
                .mask {
                    ZStack {
                        // The line.
                        NotchEdgeShape(cornerRadius: radius, shoulder: shoulder)
                            .stroke(lineWidth: 1.6)
                        // A soft inner bloom, so the edge reads as lit glass
                        // rather than a drawn outline.
                        NotchEdgeShape(cornerRadius: radius, shoulder: shoulder)
                            .stroke(lineWidth: 9)
                            .blur(radius: 6)
                            .opacity(0.6)
                    }
                }
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: clearTop)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                        Color.black
                    }
                }
        }
        .allowsHitTesting(false)
        .onAppear { if drifting { spin() } }
        .onChange(of: drifting) { _, now in
            if now { spin() } else {
                withAnimation(Motion.contentFade) { turned = false }
            }
        }
    }

    private func spin() {
        withAnimation(Motion.rimDrift.repeatForever(autoreverses: false)) { turned = true }
    }

    /// Four colours around the edge. From an accent: the accent and its two
    /// neighbours on the colour wheel, plus a pale highlight, so any cover
    /// gives an iridescent rather than a single-colour edge.
    private var palette: [Color] {
        guard let accent,
              let c = NSColor(accent).usingColorSpace(.sRGB) else {
            return [Color(red: 0.45, green: 0.85, blue: 1.0),
                    Color(red: 0.62, green: 0.45, blue: 1.0),
                    Color(red: 1.0, green: 0.55, blue: 0.85),
                    Color(red: 1.0, green: 0.82, blue: 0.55)]
        }
        let h = c.hueComponent, s = max(0.45, c.saturationComponent)
        func hue(_ shift: CGFloat, _ b: CGFloat = 1) -> Color {
            Color(hue: (h + shift + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b)
        }
        return [hue(0), hue(0.14), Color(hue: h, saturation: 0.15, brightness: 1), hue(-0.14)]
    }
}
