// Tests for the per-app quiet list.

import Foundation

func testQuietApps() {
    let own = "com.example.aloenotch"
    var list = QuietApps.adding(["com.apple.Keynote"], to: [], ownID: own)
    expect(list == ["com.apple.Keynote"], "an app can be added")

    list = QuietApps.adding(["com.apple.Keynote", "com.blackmagic.resolve"], to: list, ownID: own)
    expect(list == ["com.apple.Keynote", "com.blackmagic.resolve"], "adding again doesn't duplicate, and order is kept")

    list = QuietApps.adding([own], to: list, ownID: own)
    expect(!list.contains(own), "AloeNotch can't quiet itself")

    expect(QuietApps.isQuiet(frontmost: "com.apple.Keynote", list: list), "a listed app in front is quiet")
    expect(!QuietApps.isQuiet(frontmost: "com.apple.Safari", list: list), "an unlisted app isn't")
    expect(!QuietApps.isQuiet(frontmost: nil, list: list), "no frontmost app isn't")
    expect(!QuietApps.isQuiet(frontmost: "com.apple.Keynote", list: []), "an empty list quiets nothing")
}
