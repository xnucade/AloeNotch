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
    /// indicator.
    case peek(Peek)
    /// Full panel, dropped down below the notch.
    case expanded

    enum Peek: Equatable {
        /// Now-playing artwork + equalizer. Ambient and long-lived.
        case media
        /// A transient announcement — see `LiveActivity`. Carries only how much
        /// room it needs, not what it is: the state machine decides *how big*
        /// the strip should be, and the activity itself decides what goes in it.
        case activity(ActivitySize)
    }

    /// How much wing a transient announcement needs. Three steps rather than a
    /// free measurement so the strip only ever settles at widths that have been
    /// looked at.
    enum ActivitySize: Equatable {
        /// A symbol and nothing else.
        case compact
        /// A symbol and a short value — a percentage, a count.
        case regular
        /// A symbol and a bar, or a name long enough to need room.
        case wide
    }

    var isExpanded: Bool { self == .expanded }

    /// Short name for diagnostics.
    var debugName: String {
        switch self {
        case .collapsed:                  "collapsed"
        case .peek(.media):               "peek(media)"
        case .peek(.activity(.compact)):  "peek(activity/compact)"
        case .peek(.activity(.regular)):  "peek(activity/regular)"
        case .peek(.activity(.wide)):     "peek(activity/wide)"
        case .expanded:                   "expanded"
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
        /// Held open by the keyboard shortcut. A pointer leaves on its own; a
        /// keyboard-opened panel has no pointer to leave, so it stays until it
        /// is toggled shut.
        var isPinned = false
        /// The size of the transient announcement showing, if any. Which
        /// announcement it is does not matter here — the queue in
        /// `LiveActivityCenter` has already picked a winner.
        var activity: PanelState.ActivitySize?
        var mediaPlaying = false
        var showMedia = true

        init(isHovering: Bool = false,
             isPinned: Bool = false,
             activity: PanelState.ActivitySize? = nil,
             mediaPlaying: Bool = false,
             showMedia: Bool = true) {
            self.isHovering = isHovering
            self.isPinned = isPinned
            self.activity = activity
            self.mediaPlaying = mediaPlaying
            self.showMedia = showMedia
        }
    }

    /// Highest priority first:
    ///
    /// 1. **Hovering, or pinned open by the shortcut** — the user is actively
    ///    asking for the panel, which beats anything the app wants to
    ///    volunteer.
    /// 2. **A live activity** — transient and time-critical. A volume readout
    ///    that arrives late is useless, and a "device connected" that waits for
    ///    the track to change has stopped being news.
    /// 3. **Media** — ambient and long-lived; it can wait, and it comes back on
    ///    its own once the transient state clears.
    static func state(for i: Inputs) -> PanelState {
        if i.isHovering || i.isPinned { return .expanded }
        if let size = i.activity { return .peek(.activity(size)) }
        if i.showMedia && i.mediaPlaying { return .peek(.media) }
        return .collapsed
    }
}
