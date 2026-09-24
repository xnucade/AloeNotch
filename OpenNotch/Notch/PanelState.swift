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
        /// Two things at once: media keeps the island, and a resident
        /// activity (a running timer) pinches off beside it as its own
        /// bubble. The size is the bubble's, not the strip's — the strip is
        /// always the media peek.
        case split(ActivitySize)
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

    /// The detached bubble's size, when there is one.
    var bubble: ActivitySize? {
        if case .peek(.split(let size)) = self { size } else { nil }
    }

    /// Whether the main strip is showing the media peek (alone or split).
    var showsMedia: Bool {
        switch self {
        case .peek(.media), .peek(.split): true
        default: false
        }
    }

    /// Short name for diagnostics.
    var debugName: String {
        switch self {
        case .collapsed:                  "collapsed"
        case .peek(.media):               "peek(media)"
        case .peek(.activity(.compact)):  "peek(activity/compact)"
        case .peek(.activity(.regular)):  "peek(activity/regular)"
        case .peek(.activity(.wide)):     "peek(activity/wide)"
        case .peek(.split(.compact)):     "peek(split/compact)"
        case .peek(.split(.regular)):     "peek(split/regular)"
        case .peek(.split(.wide)):        "peek(split/wide)"
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
        /// The activity is a resident one — true until something stops being
        /// true (a timer running) — rather than an announcement. Only a
        /// resident can share the strip with media; an announcement is brief
        /// and time-critical, so it takes the whole strip.
        var activityIsResident = false
        var mediaPlaying = false
        var showMedia = true

        init(isHovering: Bool = false,
             isPinned: Bool = false,
             activity: PanelState.ActivitySize? = nil,
             activityIsResident: Bool = false,
             mediaPlaying: Bool = false,
             showMedia: Bool = true) {
            self.isHovering = isHovering
            self.isPinned = isPinned
            self.activity = activity
            self.activityIsResident = activityIsResident
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
    ///
    /// Except that 2 and 3 can share: a *resident* activity alongside media
    /// splits the island rather than hiding the music until the timer ends.
    static func state(for i: Inputs) -> PanelState {
        if i.isHovering || i.isPinned { return .expanded }
        let media = i.showMedia && i.mediaPlaying
        if let size = i.activity {
            return i.activityIsResident && media ? .peek(.split(size)) : .peek(.activity(size))
        }
        if media { return .peek(.media) }
        return .collapsed
    }
}
