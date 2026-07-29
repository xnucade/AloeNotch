import SwiftUI
import AppKit

/// Behind-window frost: the real desktop, blurred, showing through the window.
///
/// This has to be an `NSVisualEffectView` with `blendingMode = .behindWindow`.
/// SwiftUI's own `Material` (`.ultraThinMaterial` and friends) only blends with
/// content *inside* the app, so over a window it just produces a flat grey
/// wash — it cannot see the desktop at all. Behind-window blending is the only
/// thing that actually samples what is behind the window.
///
/// It also requires the hosting window to be non-opaque with a clear background
/// (see `configureForGlass`), otherwise the window's own opaque backing is
/// composited underneath and there is nothing to see through.
struct FrostBackdrop: NSViewRepresentable {
    /// `.sidebar` is the Finder/Mail sidebar material, and it is the one that
    /// reads as "translucent with some frost" over a whole window. It is also
    /// `GlassIntensity.medium` in Design/Theme.swift, which is where the
    /// user-facing intensity choice maps to a material.
    ///
    /// The two obvious neighbours are both wrong as a default here.
    /// `.hudWindow` is the thinnest material there is, so a saturated wallpaper
    /// comes through almost unattenuated and swamps secondary text.
    /// `.underWindowBackground` is not a window frost at all despite the name —
    /// it is meant for the region *under* a window, and across a full window it
    /// collapses to a flat grey wash that samples nothing.
    var material: NSVisualEffectView.Material = GlassIntensity.medium.material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        // `.active` keeps the frost live even when the window is not key;
        // `.followsWindowActiveState` makes it drop to grey on blur.
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
    }
}

extension NSWindow {
    /// Make a window able to show the desktop through it.
    ///
    /// `.fullSizeContentView` is the one that is easy to miss:
    /// `titlebarAppearsTransparent` only removes the titlebar's *own* material,
    /// it does not extend the content view underneath it. Without it the
    /// content stays inset below the titlebar, so the frost stops short and the
    /// traffic lights and title sit on a bare strip of desktop.
    ///
    /// The title text goes with it — over a transparent titlebar it draws
    /// straight onto the wallpaper with no plate behind it, and both windows
    /// already name themselves in their content.
    func configureForGlass() {
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        styleMask.insert(.fullSizeContentView)
        isMovableByWindowBackground = true
    }
}

// MARK: - Panel surface

/// The one place that decides how a card is filled, so the glass preference is
/// honoured everywhere without each view re-implementing the fallback.
///
/// Glass on is Liquid Glass proper, floating over the frosted window. Glass off
/// is an opaque panel — the point of the switch is legibility, so the fallback
/// has to actually be solid rather than slightly-less-transparent glass.
private struct PanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    }
            }
        }
    }
}

extension View {
    /// Card background that respects the user's Liquid Glass preference.
    func panelSurface(cornerRadius: CGFloat, glass: Bool) -> some View {
        modifier(PanelSurface(cornerRadius: cornerRadius, enabled: glass))
    }

    /// Capsule variant, for the settings tab bar.
    @ViewBuilder
    func capsuleSurface(glass: Bool, interactive: Bool = false) -> some View {
        if glass {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            self.background {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
            }
        }
    }

    /// Bordered button that becomes glass when the preference is on.
    @ViewBuilder
    func glassButtonStyle(_ enabled: Bool) -> some View {
        if enabled { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    /// The one call-to-action button per screen.
    @ViewBuilder
    func glassProminentButtonStyle(_ enabled: Bool) -> some View {
        if enabled { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }

    /// Frosted window background, honouring the preference. Glass off gets a
    /// normal opaque window so the material never fights legibility.
    ///
    /// System Reduce Transparency forces the solid path regardless of the app's
    /// own switch — it reuses the same fallback rather than introducing a
    /// second one, so there is only ever one non-glass appearance to maintain.
    @ViewBuilder
    func frostedWindowBackground(_ enabled: Bool) -> some View {
        modifier(FrostedWindowBackground(enabled: enabled))
    }
}

private struct FrostedWindowBackground: ViewModifier {
    let enabled: Bool
    @ObservedObject private var a11y = AccessibilityPreferences.shared
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        Group {
            if enabled && !a11y.reduceTransparency {
                content.background(
                    FrostBackdrop(material: settings.glassIntensity.material)
                        .ignoresSafeArea()
                )
            } else {
                content.background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            }
        }
        // Windows only. The notch panel never routes through here — it is pure
        // black in every state, which is what lets it vanish into the cutout.
        .preferredColorScheme(settings.windowTheme.colorScheme)
        .tint(settings.accent)
    }
}
