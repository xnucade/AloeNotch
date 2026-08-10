import Foundation

/// What the notch surface is currently showing.
///
/// This used to be a `Bool` plus a peek condition (`showMedia && isPlaying`)
/// evaluated independently in the view *and* in the window controller's
/// hit-testing — two places deriving the same truth, free to disagree. Making
/// it one value means the drawn size and the clickable size are computed from
/// the same thing, and it gives the collapsed → peek → expanded morph a single
/// property for one spring to drive.
///
/// Deliberately free of SwiftUI and AppKit so it can be compiled and tested on
/// its own (see `scripts/run-tests.sh`).
enum PanelState: Equatable {
    /// Bare strip, hugging the hardware notch. The app is invisible here.
    case collapsed
    /// Strip grown into "wings" either side of the notch, showing a glanceable
    /// indicator. The kinds need different widths, so they are not one case.
    case peek(Peek)
    /// Full panel, dropped down below the notch.
    case expanded

    enum Peek: Equatable {
        /// Now-playing artwork + equalizer.
        case media
        /// Volume / brightness readout, which needs more room than media.
        case hud
        /// Transient acknowledgement that power was just connected.
        case charging
    }

    var isExpanded: Bool { self == .expanded }

    /// Short name for diagnostics.
    var debugName: String {
        switch self {
        case .collapsed:        "collapsed"
        case .peek(.media):     "peek(media)"
        case .peek(.hud):       "peek(hud)"
        case .peek(.charging):  "peek(charging)"
        case .expanded:         "expanded"
        }
    }
}

/// Decides what the panel should be showing, from the inputs that can change it.
///
/// Pulled out of `NotchViewModel` as a pure function so the priority order can
/// actually be tested. That ordering is the kind of thing that breaks silently:
/// every input is individually plausible, so a wrong precedence doesn't crash or
/// look obviously broken — it just means the charger acknowledgement never
/// appears while music plays, or a HUD gets swallowed, and nobody notices for a
/// release or two.
enum PanelStateReducer {
    struct Inputs {
        /// Pointer inside the active region.
        var isHovering = false
        /// A volume/brightness readout is currently up.
        var hasHUD = false
        /// Power was connected within the last couple of seconds.
        var isCharging = false
        var mediaPlaying = false
        var showMedia = true

        init(isHovering: Bool = false, hasHUD: Bool = false, isCharging: Bool = false,
             mediaPlaying: Bool = false, showMedia: Bool = true) {
            self.isHovering = isHovering
            self.hasHUD = hasHUD
            self.isCharging = isCharging
            self.mediaPlaying = mediaPlaying
            self.showMedia = showMedia
        }
    }

    /// Highest priority first:
    ///
    /// 1. **Hovering** — the user is actively asking for the panel, which beats
    ///    anything the app wants to volunteer.
    /// 2. **HUD** — transient and time-critical; a volume readout that arrives
    ///    late is useless.
    /// 3. **Charging** — also transient, and a direct response to something the
    ///    user physically just did, so it outranks ambient media.
    /// 4. **Media** — ambient and long-lived; it can wait, and it comes back on
    ///    its own once the transient states clear.
    static func state(for i: Inputs) -> PanelState {
        if i.isHovering { return .expanded }
        if i.hasHUD { return .peek(.hud) }
        if i.isCharging { return .peek(.charging) }
        if i.showMedia && i.mediaPlaying { return .peek(.media) }
        return .collapsed
    }
}
