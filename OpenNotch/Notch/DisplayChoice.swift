import Foundation

/// Which display the notch lives on.
///
/// Pure, so the policy can be tested without screens: `NotchGeometry`
/// describes each connected display as a `Candidate` and asks for an index.
enum DisplayChoice: String, CaseIterable, Identifiable {
    /// The built-in display while the lid is open; the main display (the one
    /// with the menu bar) when it's closed. The right answer for nearly
    /// everyone, which is why it's the default.
    case automatic
    /// Always the display with the menu bar, even with the lid open.
    case main
    /// The display picked with "Move Here", remembered by name. Falls back to
    /// automatic while that display isn't connected.
    case chosen

    var id: String { rawValue }

    struct Candidate: Equatable {
        var name: String
        var isBuiltIn: Bool
    }

    /// The display to use, as an index into `candidates`, whose first element
    /// must be the menu-bar display (as `NSScreen.screens` orders them). Nil
    /// only when there are no displays at all.
    static func pick(_ choice: DisplayChoice, pinnedName: String?,
                     from candidates: [Candidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        switch choice {
        case .main:
            return 0
        case .chosen:
            if let pinnedName, let i = candidates.firstIndex(where: { $0.name == pinnedName }) {
                return i
            }
            return pick(.automatic, pinnedName: nil, from: candidates)
        case .automatic:
            return candidates.firstIndex(where: \.isBuiltIn) ?? 0
        }
    }
}
