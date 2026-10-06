import Foundation

/// MediaRemote's shuffle modes, as the adapter reports and sets them.
enum ShuffleMode: Int {
    case off = 1, albums = 2, tracks = 3

    /// From a payload value. Absent, unknown (0) or anything else is nil:
    /// the player isn't saying, so there is nothing to show.
    init?(payload value: Any?) {
        guard let raw = (value as? NSNumber)?.intValue else { return nil }
        self.init(rawValue: raw)
    }

    /// Shuffling by album counts as on, and turns off, as in Music.
    var toggled: ShuffleMode { self == .off ? .tracks : .off }
}

/// MediaRemote's repeat modes, as the adapter reports and sets them.
enum RepeatMode: Int {
    case off = 1, one = 2, all = 3

    init?(payload value: Any?) {
        guard let raw = (value as? NSNumber)?.intValue else { return nil }
        self.init(rawValue: raw)
    }

    /// The order Music steps through: off, all, one, off.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
