// Tests for the panel state precedence.
//
// Run with ./scripts/run-tests.sh — no XCTest, no Xcode target. These cover
// pure logic extracted from the view model precisely so it can be exercised
// without standing up seven managers, a window and a screen.

func testPanelState() {
    typealias I = PanelStateReducer.Inputs
    let state = PanelStateReducer.state(for:)

    // Nothing happening.
    expect(state(I()) == .collapsed, "idle is collapsed")

    // Each input on its own.
    expect(state(I(isHovering: true)) == .expanded, "hover expands")
    expect(state(I(activity: .wide)) == .peek(.activity(.wide)), "an activity peeks")
    expect(state(I(mediaPlaying: true)) == .peek(.media), "playback peeks")

    // The activity carries its own width through to the state, because that is
    // what sizes the strip.
    expect(state(I(activity: .compact)) == .peek(.activity(.compact)), "compact size survives")
    expect(state(I(activity: .regular)) == .peek(.activity(.regular)), "regular size survives")
    expect(state(I(activity: .compact)) != state(I(activity: .wide)),
           "different sizes are different states — they map to different strip widths")

    // The keyboard shortcut pins the panel open. A pointer leaves on its own;
    // a keyboard-opened panel has nothing to leave, so nothing below it in the
    // chain may take it back.
    expect(state(I(isPinned: true)) == .expanded, "the shortcut expands")
    expect(state(I(isHovering: false, isPinned: true)) == .expanded,
           "pinned survives the pointer leaving — otherwise it shuts the moment you mouse away")
    expect(state(I(isPinned: true, activity: .wide)) == .expanded,
           "pinned beats an activity")
    expect(state(I(isPinned: true, mediaPlaying: true)) == .expanded,
           "pinned beats media")
    expect(state(I(isPinned: true, mediaPlaying: true, showMedia: false)) == .expanded,
           "pinned ignores module switches")

    // Precedence. These are the assertions that matter: every input is
    // individually plausible, so a wrong order does not crash or look obviously
    // broken — it just quietly swallows a state.
    expect(state(I(isHovering: true, activity: .wide)) == .expanded,
           "hover beats an activity")
    expect(state(I(isHovering: true, mediaPlaying: true)) == .expanded,
           "hover beats media")
    expect(state(I(activity: .regular, mediaPlaying: true)) == .peek(.activity(.regular)),
           "an activity beats media — a volume readout mid-track must not wait")

    // All at once resolves to the top of the chain.
    expect(state(I(isHovering: true, activity: .wide, mediaPlaying: true)) == .expanded,
           "hover wins over everything")

    // The media module being off must suppress the peek, not just the panel
    // content — otherwise the strip widens for something it will not draw.
    expect(state(I(mediaPlaying: true, showMedia: false)) == .collapsed,
           "media disabled suppresses the peek entirely")
    expect(state(I(activity: .regular, mediaPlaying: true, showMedia: false))
           == .peek(.activity(.regular)),
           "media disabled does not suppress activities")

    // isExpanded is used for the corner radius and the hairline edge, so it
    // must be true for exactly one case.
    expect(PanelState.expanded.isExpanded, "expanded.isExpanded")
    expect(!PanelState.collapsed.isExpanded, "collapsed is not expanded")
    expect(!PanelState.peek(.media).isExpanded, "media peek is not expanded")
    expect(!PanelState.peek(.activity(.wide)).isExpanded, "activity peek is not expanded")

    // Peek kinds are distinct — they map to different strip widths, and
    // collapsing two of them would size the strip wrongly.
    expect(PanelState.peek(.media) != PanelState.peek(.activity(.compact)),
           "media and an activity are different peeks even at the same width")
}
