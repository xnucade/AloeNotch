// Tests for the two pure pieces behind the motion and readout settings.
//
// Animation *feel* is not unit-testable and is not asserted here. What is
// testable is everything around it: that a stored value cannot escape its
// range, that a preset round-trips, and that a colour dark enough to vanish
// against the notch gets lifted rather than shipped.

import AppKit
import SwiftUI

func testMotionPersonality() {
    // The preset a stored scalar resolves back to. This is what lets the
    // segmented control show a selection instead of guessing.
    expect(MotionPersonality.matching(0.00) == .calm, "0 is Calm")
    expect(MotionPersonality.matching(0.10) == .standard, "0.10 is Standard")
    expect(MotionPersonality.matching(0.45) == .lively, "0.45 is Lively")
    expect(MotionPersonality.matching(0.22) == nil,
           "a value between presets resolves to no preset, so the UI can say Custom")

    for p in MotionPersonality.allCases {
        expect(MotionPersonality.matching(p.bounce) == p, "\(p.title) round-trips through its own scalar")
    }

    // Standard has to stay where it was, or every existing install's notch
    // changes behaviour on update.
    expect(MotionPersonality.standard.bounce == 0.10,
           "Standard is still the value the app shipped before this was a choice")

    // Clamping is the only thing between a corrupt default and a broken spring.
    expect(MotionPersonality.clamp(-1) == 0, "negative clamps to zero")
    expect(MotionPersonality.clamp(9) == 0.55, "absurd clamps to the ceiling")
    expect(MotionPersonality.clamp(0.22) == 0.22, "a value in range is left alone")
    expect(MotionPersonality.clamp(MotionPersonality.range.lowerBound) == 0, "the floor is in range")
    expect(MotionPersonality.clamp(MotionPersonality.range.upperBound) == 0.55, "the ceiling is in range")

    // Calm must be genuinely flat, not nearly flat.
    expect(MotionPersonality.calm.bounce == 0, "Calm does not overshoot at all")
    expect(MotionPersonality.lively.bounce > MotionPersonality.standard.bounce,
           "Lively is livelier than Standard")
    // The reason Lively is 0.45 and not 0.30: extraBounce is very non-linear,
    // and below ~0.35 the overshoot is too small to see on a 208pt panel.
    expect(MotionPersonality.lively.bounce >= 0.35,
           "Lively is past the point where overshoot becomes visible")
}

func testHUDContrast() {
    // A bar the user cannot see is worse than a white one.
    let nearBlack = Color(.sRGB, red: 0.04, green: 0.04, blue: 0.05, opacity: 1)
    expect(HUDContrast.luminance(of: nearBlack) < HUDContrast.minimumLuminance,
           "near-black is below the floor")
    expect(HUDContrast.luminance(of: HUDContrast.legible(nearBlack)) >= HUDContrast.luminance(of: nearBlack),
           "lifting a dark colour never makes it darker")

    // Anything already legible is returned untouched — the floor lifts, it
    // does not normalise every colour to the same brightness.
    let midBlue = Color(.sRGB, red: 0.24, green: 0.61, blue: 1.0, opacity: 1)
    let before = HUDContrast.luminance(of: midBlue)
    expect(before >= HUDContrast.minimumLuminance, "a mid blue already passes")
    expect(abs(HUDContrast.luminance(of: HUDContrast.legible(midBlue)) - before) < 0.0001,
           "a colour that already passes is left exactly as chosen")

    expect(abs(HUDContrast.luminance(of: .white) - 1.0) < 0.01, "white is full luminance")
    expect(HUDContrast.luminance(of: .black) < 0.001, "black is none")

    // Green reads brighter than blue at the same numeric value; the weighting
    // has to be perceptual or a "dark" green would get lifted unnecessarily.
    let g = Color(.sRGB, red: 0, green: 0.5, blue: 0, opacity: 1)
    let b = Color(.sRGB, red: 0, green: 0, blue: 0.5, opacity: 1)
    expect(HUDContrast.luminance(of: g) > HUDContrast.luminance(of: b),
           "luminance is perceptual, not a plain channel average")
}
