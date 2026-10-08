import Foundation

/// The apps the notch keeps quiet over, as bundle identifiers.
///
/// Full-screen detection covers games and video, but not the windowed app
/// you'd still rather it left alone — a presentation in a window, a video
/// editor with its timeline up against the menu bar, a game that doesn't go
/// full screen. Listing an app here gives it the full-screen treatment
/// whenever it's in front.
///
/// Bundle identifiers rather than paths, so an app that moves or updates is
/// still the same app.
enum QuietApps {
    /// The list with `added` appended — order kept, duplicates and AloeNotch
    /// itself dropped. Its own Settings window is in front whenever this list
    /// is being edited, so listing it would quiet the notch while you look
    /// at the setting that did it.
    static func adding(_ added: [String], to list: [String], ownID: String?) -> [String] {
        var result = list
        for id in added where id != ownID && !result.contains(id) {
            result.append(id)
        }
        return result
    }

    static func isQuiet(frontmost: String?, list: [String]) -> Bool {
        guard let frontmost else { return false }
        return list.contains(frontmost)
    }
}
