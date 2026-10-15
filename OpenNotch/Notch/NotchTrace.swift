import os

/// Breadcrumbs for bugs that only show up on someone else's Mac: state
/// changes, announcements, and which display's panel is active. Kinds and
/// states only, never titles or anything the user typed or played.
///
/// Read with:
/// `log show --last 10m --predicate 'subsystem == "com.kadeslab.AloeNotch" AND category == "trace"'`
enum NotchTrace {
    static let log = Logger(subsystem: "com.kadeslab.AloeNotch", category: "trace")
}
