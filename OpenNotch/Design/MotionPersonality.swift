import SwiftUI
import AppKit

/// Pure value types behind the motion and readout preferences.
///
/// Split out of `Theme.swift` for the same reason `PanelState` and
/// `CountdownState` are separate files: everything here is a pure function of
/// its input, with no reference to `AppSettings` or any running app, which is
/// exactly what `scripts/run-tests.sh` can compile and exercise on its own.
/// `Motion` itself cannot go here — it reads live preferences by design.

/// How lively the panel is when it opens.
///
/// One scalar behind three names. A raw "extraBounce 0.0–0.40" slider is a
/// developer control: it asks every user to pick a number with no reference
/// point. The presets are what almost everyone touches; the scalar is there
/// for the person who wants the value between two of them.
enum MotionPersonality: String, CaseIterable, Identifiable {
    case calm, standard, lively
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm:     "Calm"
        case .standard: "Standard"
        case .lively:   "Lively"
        }
    }

    /// SwiftUI's `extraBounce` maps to a damping ratio of `1 - bounce`, and
    /// the overshoot it produces is very non-linear. Measured:
    ///
    ///     0.10 →  0.15%   0.30 →  4.6%    0.45 → 12.6%
    ///     0.20 →  1.5%    0.40 →  9.5%    0.55 → 20.5%
    ///
    /// Which is why Standard looks flat: at 0.15% the panel does not visibly
    /// overshoot at all. Lively is 0.45 rather than something that *sounds*
    /// livelier, because that is where the bounce becomes a thing you can
    /// actually see on a 208pt panel.
    var bounce: Double {
        switch self {
        case .calm:     0.00
        case .standard: 0.10   // what the app shipped before this was a choice
        case .lively:   0.45
        }
    }

    var detail: String {
        switch self {
        case .calm:     "Lands flat, like the rest of macOS."
        case .standard: "A little overshoot. The default."
        case .lively:   "Visible bounce, still settles fast."
        }
    }

    /// The ceiling is 0.55 — about 20% overshoot. Past that the panel visibly
    /// wobbles rather than bounces, and on a shape anchored to the top of the
    /// screen that reads as a bug.
    static let range: ClosedRange<Double> = 0...0.55

    static func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The preset a stored scalar corresponds to, or nil if it sits between
    /// two of them — which is how the UI knows to show "Custom" as selected.
    static func matching(_ value: Double) -> MotionPersonality? {
        allCases.first { abs($0.bounce - value) < 0.001 }
    }
}

/// Where the volume and brightness bars get their colour.
enum HUDTintMode: String, CaseIterable, Identifiable {
    /// White, as the app has always drawn them.
    case monochrome
    /// Both follow the app's accent.
    case accent
    /// Volume and brightness each get their own.
    case perKind
    /// Both take the colour the current artwork is already lending the glow.
    case artwork
    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome: "White"
        case .accent:     "Accent"
        case .perKind:    "Custom"
        case .artwork:    "Artwork"
        }
    }

    var detail: String {
        switch self {
        case .monochrome: "The readouts stay white."
        case .accent:     "They follow the accent colour above."
        case .perKind:    "Volume and brightness get their own colours."
        case .artwork:    "They take the colour of whatever is playing, and go back to white when nothing is."
        }
    }
}

/// Readable against the notch's pure black.
///
/// A colour well will happily hand back `#101014`, and a level bar the user
/// cannot see is worse than a white one. Rather than rejecting the choice,
/// lift it: the user keeps the hue they picked and gets a version of it that
/// reads.
enum HUDContrast {
    /// Relative luminance floor, chosen so a mid-grey passes and near-black
    /// does not. Lower than a WCAG text threshold on purpose — this is a 4pt
    /// bar, not body copy, and clamping too hard would wash out deep colours
    /// people legitimately want.
    static let minimumLuminance: Double = 0.22

    static func luminance(of color: Color) -> Double {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent)
             + 0.7152 * lin(c.greenComponent)
             + 0.0722 * lin(c.blueComponent)
    }

    /// The colour, brightened toward white only as far as the floor requires.
    static func legible(_ color: Color) -> Color {
        let l = luminance(of: color)
        guard l < minimumLuminance, l.isFinite else { return color }
        let mix = min(1, (minimumLuminance - l) / max(minimumLuminance, 0.0001))
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return Color(
            .sRGB,
            red:   Double(c.redComponent)   + (1 - Double(c.redComponent))   * mix,
            green: Double(c.greenComponent) + (1 - Double(c.greenComponent)) * mix,
            blue:  Double(c.blueComponent)  + (1 - Double(c.blueComponent))  * mix,
            opacity: 1
        )
    }
}
