// Tests for which display the notch lives on.

func testDisplayChoice() {
    typealias C = DisplayChoice.Candidate
    let external = C(name: "Studio Display", isBuiltIn: false)
    let laptop = C(name: "Built-in Retina Display", isBuiltIn: true)
    let other = C(name: "DELL U2723QE", isBuiltIn: false)

    // The menu-bar display comes first, as NSScreen.screens orders them.
    let docked = [external, laptop, other]
    let clamshell = [external, other]

    expect(DisplayChoice.pick(.automatic, pinnedName: nil, from: docked) == 1,
           "automatic prefers the built-in display while the lid is open")
    expect(DisplayChoice.pick(.automatic, pinnedName: nil, from: clamshell) == 0,
           "and the menu-bar display with the lid closed")
    expect(DisplayChoice.pick(.main, pinnedName: nil, from: docked) == 0,
           "main is always the menu-bar display")
    expect(DisplayChoice.pick(.chosen, pinnedName: "DELL U2723QE", from: docked) == 2,
           "a chosen display is found by name")
    expect(DisplayChoice.pick(.chosen, pinnedName: "Gone", from: docked) == 1,
           "a chosen display that isn't connected falls back to automatic")
    expect(DisplayChoice.pick(.automatic, pinnedName: nil, from: []) == nil, "no displays, no pick")
}
