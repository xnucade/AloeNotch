import SwiftUI
import AppKit
import Combine

/// Design tokens for the whole app.
///
/// Before this existed, corner radii, spacings and animation curves were
/// literals spread across eight view files — the expanded panel's 26pt radius
/// was computed independently in two places in `NotchRootView` alone, which is
/// exactly how a surface ends up subtly inconsistent with itself. Everything
/// visual that more than one view needs to agree on lives here.
///
/// Nothing in this file changes how the app currently looks. It is the shared
/// vocabulary the animation work is built on.

// MARK: - Motion

/// Every animation curve in the app.
///
/// These are springs, not eased curves, and that is deliberate: a spring can be
/// retargeted mid-flight, so reversing a half-finished expand continues from
/// wherever it is instead of snapping to a new start. `.smooth` is SwiftUI's
/// critically-damped fluid spring — `extraBounce` above 0 lets it overshoot a
/// touch, which reads as weight.
///
/// Ask for these through `Motion.resolve(_:reduceMotion:)` rather than using
/// them raw, so Reduce Motion is honored in one place instead of at every call
/// site.
enum Motion {
    /// User-facing speed multiplier: >1 is faster, <1 slower.
    ///
    /// Applied by dividing durations, so "1.5×" genuinely means the animation
    /// takes two-thirds as long. Read from settings on each access rather than
    /// captured once, so the Appearance slider previews live — these are
    /// computed properties for that reason, not `let` constants.
    private static var speed: Double {
        max(0.25, min(3.0, AppSettings.shared.animationSpeed))
    }

    private static func scaled(_ duration: Double) -> Double { duration / speed }

    /// Opening: a little overshoot, so the panel arrives with momentum rather
    /// than easing politely into place.
    static var expand: Animation { .smooth(duration: scaled(0.40), extraBounce: 0.10) }

    /// Closing: no bounce. A panel that overshoots on the way out reads as
    /// unstable, and it is retreating to a shape that must land exactly on the
    /// hardware notch.
    static var collapse: Animation { .smooth(duration: scaled(0.32)) }

    /// Transient readouts and the collapsed strip's width changes (wings
    /// growing for media or a HUD). Quicker, because nothing is travelling far.
    static var hud: Animation { .smooth(duration: scaled(0.28)) }

    /// Small state flips on controls — hover, press, selection.
    static var micro: Animation { .snappy(duration: scaled(0.20)) }

    /// Artwork colour drifting from one track's accent to the next. Slow on
    /// purpose: this is ambient light, and light does not snap.
    static var accentShift: Animation { .smooth(duration: scaled(0.80)) }

    /// Content that fades rather than travels.
    static var contentFade: Animation { .smooth(duration: scaled(0.30)) }

    /// A transient element announcing itself — the charging bolt, a badge.
    /// Bouncier than anything else here on purpose: it should feel like it
    /// landed, and it is on screen too briefly to be annoying.
    static var arrival: Animation { .snappy(duration: scaled(0.34), extraBounce: 0.35) }

    /// A value ticking inside an already-visible readout (a HUD level bar).
    /// Short, because the container is not moving and the eye is on the number.
    static var readout: Animation { .smooth(duration: scaled(0.18)) }

    // Ambient loops. Deliberately *not* scaled by the speed preference: these
    // are continuous background motion rather than responses to an action, and
    // speeding them up reads as agitation rather than responsiveness.

    /// The charging bolt breathing.
    static let ambientPulse = Animation.easeInOut(duration: 0.9)

    /// One equalizer bar's rise and fall. Callers stagger their own phase.
    static let equalizerBar = Animation.easeInOut(duration: 0.5)

    /// The highlight sweeping across a charging battery fill.
    static let chargeShimmer = Animation.linear(duration: 1.2)

    // MARK: Choreography
    //
    // The container leads and its contents follow. Moving both on the same
    // beat is what makes a panel read as a picture that resized, rather than a
    // shape that opened and then filled.

    /// How far behind the container's own motion content should start.
    static var contentLag: Double { 0.06 / speed }

    /// Gap between successive rows or icons in a staggered reveal. Small
    /// enough to read as a cascade rather than a queue.
    static var stagger: Double { 0.03 / speed }

    /// Delay for the `index`-th element of a staggered group, including the lag
    /// behind the container. Returns 0 under Reduce Motion so nothing waits.
    static func entranceDelay(_ index: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : contentLag + Double(index) * stagger
    }

    /// Reduce Motion replacement: a plain cross-fade with no travel, scale or
    /// bounce. The system asks for *less motion*, not *no feedback*, so state
    /// changes still register — they just stop moving through space.
    static let reduced = Animation.easeInOut(duration: 0.20)

    /// The single gate for Reduce Motion. Pass any token through this.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// How a single element arrives inside the morphing container.
    ///
    /// Two things make this read as one object reshaping rather than a panel
    /// that opened and then filled:
    ///
    /// - **The shape leads.** Content starts `Motion.contentLag` behind the
    ///   container's own motion, so the pill is already growing before anything
    ///   appears inside it. Moving both on the same beat is what makes a panel
    ///   look like a picture that resized.
    /// - **It grows into place.** Scaling up from 0.92 rather than fading at
    ///   full size means the content shares the container's direction of travel.
    ///
    /// Asymmetric on purpose: arrivals cascade, departures leave together.
    /// A reverse cascade on the way out looks like the panel is struggling to
    /// close, and the collapse is the faster animation of the two anyway.
    static func notchEntrance(index: Int = 0, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let delay = Motion.entranceDelay(index, reduceMotion: false)
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .top))
                .animation(Motion.contentFade.delay(delay)),
            removal: .opacity.animation(Motion.collapse)
        )
    }
}

/// Staggered arrival for one element inside the expanding panel.
///
/// Deliberately *not* built on `.transition`. A parent's transition takes
/// precedence over its descendants', so putting staggered transitions on rows
/// inside a container that is itself being inserted does nothing at all — the
/// subtree simply appears. That is a silent failure: the code reads as though
/// it staggers and the app looks unchanged.
///
/// Driving `opacity` and `scale` from local state flipped in `onAppear`
/// animates regardless of what the parent is doing, because it is an ordinary
/// property change on a view that already exists.
struct NotchEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            // Anchored at the top so rows grow downward out of the notch,
            // following the container rather than blooming from their centres.
            .scaleEffect(shown || reduceMotion ? 1 : 0.92, anchor: .top)
            .onAppear {
                guard !shown else { return }
                withAnimation(
                    Motion.resolve(Motion.contentFade, reduceMotion: reduceMotion)
                        .delay(Motion.entranceDelay(index, reduceMotion: reduceMotion))
                ) { shown = true }
            }
    }
}

extension View {
    /// Arrive `index` steps into the cascade. See `NotchEntrance`.
    func notchEntrance(_ index: Int) -> some View {
        modifier(NotchEntrance(index: index))
    }
}

// MARK: - Metrics

/// Sizes and spacings shared across the notch surface.
enum Metrics {
    /// Corner radius of the expanded panel. Tahoe-era curvature; inner cards
    /// derive their radii from this minus their inset so corners stay
    /// concentric.
    static let panelRadius: CGFloat = 26

    /// Corner radius of the collapsed strip. Must stay small enough that the
    /// strip's silhouette is indistinguishable from the hardware notch.
    static let collapsedRadius: CGFloat = 10

    /// Radius for the current panel state — the one place that decides, so the
    /// fill and the clip can never disagree about the shape they are drawing.
    static func radius(expanded: Bool) -> CGFloat {
        expanded ? panelRadius : collapsedRadius
    }

    /// Inner card radius, concentric with a parent of `parent` radius at
    /// `inset` points in.
    static func concentricRadius(parent: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, parent - inset)
    }

    // Expanded panel padding.
    static let panelHorizontalInset: CGFloat = 18
    static let panelBottomInset: CGFloat = 13
    /// Gap between the bottom of the physical notch and the content below it.
    static let contentTopGap: CGFloat = 6

    // Collapsed strip padding, which differs by whether there is a real notch
    // to route content around.
    static let stripInsetHardware: CGFloat = 9
    static let stripInsetSimulated: CGFloat = 14
    static let hudInsetHardware: CGFloat = 12
    static let hudInsetSimulated: CGFloat = 16

    // Now-playing artwork, collapsed and expanded. These are the two ends of
    // the matched-geometry morph.
    static let peekArtworkSize: CGFloat = 15
    static let expandedArtworkSize: CGFloat = 62
    static let peekArtworkRadius: CGFloat = 4
    static let expandedArtworkRadius: CGFloat = 13
}

// MARK: - Appearance

/// How translucent the glass surfaces are.
///
/// Backed by `NSVisualEffectView` materials rather than SwiftUI's `Material`,
/// because only `blendingMode = .behindWindow` can sample the actual desktop —
/// SwiftUI's materials blend with in-app content and produce a flat grey wash
/// over a window. See `FrostBackdrop` in GlassBackdrop.swift.
enum GlassIntensity: String, CaseIterable, Identifiable {
    case light, medium, heavy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:  "Light"
        case .medium: "Medium"
        case .heavy:  "Heavy"
        }
    }

    /// `.hudWindow` is the thinnest material; `.popover` the most opaque.
    /// `.sidebar` sits between them and is the current shipping look.
    var material: NSVisualEffectView.Material {
        switch self {
        case .light:  .hudWindow
        case .medium: .sidebar
        case .heavy:  .popover
        }
    }
}

// MARK: - Accent

/// Hand-picked accent colours.
///
/// Curated rather than a raw colour wheel because these have to stay legible in
/// two very different places: as chrome on the glass windows, and against the
/// notch's pure black. Muddy or very dark hues fail the second test badly, so
/// every swatch here is chosen with enough luminance to hold up on black.
/// A custom well sits beside them for anyone who wants an exact colour.
enum AccentPalette {
    struct Swatch: Identifiable, Hashable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) ?? .accentColor }
    }

    static let `default` = "#3D9BFF"

    static let swatches: [Swatch] = [
        Swatch(name: "Blue",   hex: "#3D9BFF"),
        Swatch(name: "Indigo", hex: "#7A7BFF"),
        Swatch(name: "Purple", hex: "#B36BFF"),
        Swatch(name: "Pink",   hex: "#FF6FA8"),
        Swatch(name: "Red",    hex: "#FF6B5E"),
        Swatch(name: "Orange", hex: "#FF9F45"),
        Swatch(name: "Green",  hex: "#4FD07A"),
        Swatch(name: "Teal",   hex: "#3FD0C9"),
    ]
}

extension Color {
    /// Parses `#RRGGBB` (the leading `#` optional). Returns nil on anything
    /// else, so a corrupted preference falls back rather than crashing.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue:  Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// `#RRGGBB` for persistence. Converts through sRGB so a colour picked in
    /// Display P3 round-trips to something sane rather than clipping oddly.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Which appearance the app's own windows use. The notch panel is not included
/// on purpose — it is pure black in every state, which is the whole reason it
/// disappears into the hardware cutout.
enum WindowTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

// MARK: - Accessibility

/// Live mirror of the two system accessibility settings that should change how
/// this app draws.
///
/// `NSWorkspace` publishes one notification for the whole
/// accessibility-display group, so both values are re-read together whenever it
/// fires. Polling would be the obvious alternative and is wrong: these change
/// rarely and the notification is exact.
final class AccessibilityPreferences: ObservableObject {
    static let shared = AccessibilityPreferences()

    /// User wants less animation. Springs collapse to short cross-fades.
    @Published private(set) var reduceMotion: Bool

    /// User wants less translucency. Glass falls back to solid surfaces —
    /// the same path the app's own "Use Liquid Glass" switch already takes,
    /// so there is one fallback to maintain rather than two.
    @Published private(set) var reduceTransparency: Bool

    private var observer: NSObjectProtocol?

    private init() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let ws = NSWorkspace.shared
            self.reduceMotion = ws.accessibilityDisplayShouldReduceMotion
            self.reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Prefer this over SwiftUI's `\.accessibilityReduceMotion`: that one is
    /// not reliably populated for views hosted in a plain `NSHostingView`
    /// outside a SwiftUI `App` scene, which is exactly how the notch panel is
    /// mounted (see NotchWindowController).
    var notchReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var notchReduceTransparency: Bool {
        get { self[ReduceTransparencyKey.self] }
        set { self[ReduceTransparencyKey.self] = newValue }
    }
}

extension View {
    /// Feed the live accessibility preferences into a view tree.
    func withAccessibilityPreferences(
        _ prefs: AccessibilityPreferences = .shared
    ) -> some View {
        modifier(AccessibilityPreferenceInjector(prefs: prefs))
    }
}

private struct AccessibilityPreferenceInjector: ViewModifier {
    @ObservedObject var prefs: AccessibilityPreferences

    func body(content: Content) -> some View {
        content
            .environment(\.notchReduceMotion, prefs.reduceMotion)
            .environment(\.notchReduceTransparency, prefs.reduceTransparency)
    }
}

// MARK: - Haptics

/// Trackpad feedback for the two moments that are genuinely physical: catching
/// a dropped file, and stepping the volume or brightness.
///
/// No capability check is needed. `defaultPerformer` is non-optional and simply
/// does nothing on hardware without a Force Touch actuator, or when the user is
/// driving a plain mouse — so guarding would only add a branch that is always
/// true on the machines where it matters.
///
/// Deliberately sparse: haptics stop reading as feedback and start reading as
/// noise the moment they fire on things the user didn't physically do.
enum Haptics {
    /// One detent. Used per volume/brightness step, matching the way macOS's
    /// own HUD ticks as the level moves.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.levelChange, performanceTime: .now)
    }

    /// The shelf catching a file. `.drawCompleted` lines the tap up with the
    /// frame that actually shows the chip landing, rather than firing while the
    /// drop is still being processed.
    static func caught() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.alignment, performanceTime: .drawCompleted)
    }
}

// MARK: - Shared control styles

/// Hover treatment for small icon controls: brighten, and lift very slightly.
///
/// Callers give their icon a *full-strength* colour and pass the resting
/// opacity here, rather than dimming the colour themselves — otherwise the two
/// opacities multiply and the hovered state never reaches full brightness.
struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.12
    var restOpacity: Double = 0.55

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hovering ? 1 : restOpacity)
            // The lift is pure travel, so Reduce Motion drops it and lets the
            // brightness change carry the affordance on its own.
            .scaleEffect(reduceMotion ? 1 : (hovering ? scale : 1))
            .animation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion),
                       value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.12, restOpacity: Double = 0.55) -> some View {
        modifier(HoverLift(scale: scale, restOpacity: restOpacity))
    }
}

/// Press-down squish. The small physical touch Apple's own controls have: a
/// control that does not move under the cursor feels like an image of a button
/// rather than a button.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.86

    @Environment(\.notchReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Reduce Motion removes the scale entirely rather than shrinking
            // it: a smaller squish is still travel, and travel is the thing
            // being opted out of. Opacity carries the press feedback instead.
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.7 : 1)
            .animation(
                Motion.resolve(.snappy(duration: 0.15), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
