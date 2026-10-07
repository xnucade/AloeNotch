import Foundation

/// The standing conditions the notch knows about, and which one it shows.
///
/// One slot was enough while the timer was the only resident. With a
/// stopwatch, a focus session and a meeting about to start all able to be true
/// at once, a single slot means whichever set itself last silently erases the
/// others — and clearing one would leave the notch empty while another is
/// still running. Each kind keeps its own entry; the highest priority shows,
/// and among equals the most recently set, because that is the one the user
/// just did something about.
struct ResidentSlots<Activity: QueueableActivity> {
    private var entries: [String: (activity: Activity, order: Int)] = [:]
    private var counter = 0

    /// What should be on the strip when no announcement is playing over it.
    var showing: Activity? {
        entries.values.max { a, b in
            a.activity.priority != b.activity.priority
                ? a.activity.priority < b.activity.priority
                : a.order < b.order
        }?.activity
    }

    /// Adds or replaces the entry for this kind. Replacing keeps its place in
    /// the recency order — a timer updating its deadline every pause shouldn't
    /// leapfrog a stopwatch the user started after it.
    mutating func set(_ activity: Activity) {
        if let existing = entries[activity.kind] {
            entries[activity.kind] = (activity, existing.order)
        } else {
            counter += 1
            entries[activity.kind] = (activity, counter)
        }
    }

    mutating func clear(kind: String) {
        entries[kind] = nil
    }

    func contains(kind: String) -> Bool { entries[kind] != nil }
}
