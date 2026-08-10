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
    expect(state(I(hasHUD: true)) == .peek(.hud), "HUD peeks")
    expect(state(I(isCharging: true)) == .peek(.charging), "charging peeks")
    expect(state(I(mediaPlaying: true)) == .peek(.media), "playback peeks")

    // Precedence, pairwise down the chain. These are the assertions that
    // matter: every input is individually plausible, so a wrong order does not
    // crash or look obviously broken — it just quietly swallows a state.
    expect(state(I(isHovering: true, hasHUD: true)) == .expanded,
           "hover beats HUD")
    expect(state(I(isHovering: true, mediaPlaying: true)) == .expanded,
           "hover beats media")
    expect(state(I(hasHUD: true, isCharging: true)) == .peek(.hud),
           "HUD beats charging")
    expect(state(I(hasHUD: true, mediaPlaying: true)) == .peek(.hud),
           "HUD beats media")
    expect(state(I(isCharging: true, mediaPlaying: true)) == .peek(.charging),
           "charging beats media — plugging in is acknowledged mid-track")

    // All at once resolves to the top of the chain.
    expect(state(I(isHovering: true, hasHUD: true, isCharging: true,
                   mediaPlaying: true)) == .expanded,
           "hover wins over everything")

    // The media module being off must suppress the peek, not just the panel
    // content — otherwise the strip widens for something it will not draw.
    expect(state(I(mediaPlaying: true, showMedia: false)) == .collapsed,
           "media disabled suppresses the peek entirely")
    expect(state(I(isCharging: true, mediaPlaying: true, showMedia: false))
           == .peek(.charging),
           "media disabled does not suppress other peeks")

    // isExpanded is used for the corner radius and the hairline edge, so it
    // must be true for exactly one case.
    expect(PanelState.expanded.isExpanded, "expanded.isExpanded")
    expect(!PanelState.collapsed.isExpanded, "collapsed is not expanded")
    expect(!PanelState.peek(.media).isExpanded, "peek is not expanded")
    expect(!PanelState.peek(.hud).isExpanded, "hud peek is not expanded")
    expect(!PanelState.peek(.charging).isExpanded, "charging peek is not expanded")

    // Peek kinds are distinct — they map to different strip widths, and
    // collapsing two of them would size the strip wrongly.
    expect(PanelState.peek(.media) != PanelState.peek(.hud), "peek kinds differ")
    expect(PanelState.peek(.hud) != PanelState.peek(.charging), "peek kinds differ")
}
