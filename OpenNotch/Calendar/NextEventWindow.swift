import Foundation

/// When the next event's countdown belongs on the strip, with no clock and no
/// calendar attached.
///
/// Ten minutes out is when "I have a meeting" turns into "I should wrap this
/// up" — earlier and the countdown is wallpaper, later and it is a scramble.
/// All-day events have no start to count to and never qualify.
enum NextEventWindow {
    static let lead: TimeInterval = 10 * 60

    struct Decision: Equatable {
        /// Index of the event to count down to, if one is inside the window.
        var showing: Int?
        /// When the answer next changes: the window opening on the next
        /// event, or the one showing starting. Nil when nothing is coming.
        var recheck: Date?
    }

    static func decide(_ events: [(start: Date, isAllDay: Bool)], now: Date) -> Decision {
        let next = events.indices
            .filter { !events[$0].isAllDay && events[$0].start > now }
            .min { events[$0].start < events[$1].start }
        guard let next else { return Decision(showing: nil, recheck: nil) }

        let start = events[next].start
        let opens = start.addingTimeInterval(-lead)
        return now >= opens
            ? Decision(showing: next, recheck: start)
            : Decision(showing: nil, recheck: opens)
    }
}
