import Foundation

/// Time-coded lyrics parsed from LRC, the format LRCLIB serves.
///
/// Pure and Foundation-only so it's tested from the shell. Handles several
/// stamps on one line (`[00:12.30][01:40.00]chorus`), two- or three-digit
/// fractions, and the `[offset:…]` tag. Metadata tags (`[ar:…]`, `[ti:…]`)
/// and word-level `<mm:ss.xx>` stamps are dropped. Empty lines are kept: they
/// mark instrumental gaps, where the notch should show no line at all.
struct SyncedLyrics: Equatable {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    let lines: [Line]

    init?(lrc: String) {
        var offset = 0.0
        var parsed: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw).trimmingCharacters(in: .whitespaces)[...]
            var stamps: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = Self.seconds(tag) {
                    stamps.append(t)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    // Positive offset means the lyrics come sooner.
                    offset = -ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let text = Self.stripWordStamps(String(rest)).trimmingCharacters(in: .whitespaces)
            parsed += stamps.map { Line(time: $0, text: text) }
        }
        guard parsed.contains(where: { !$0.text.isEmpty }) else { return nil }
        lines = parsed
            .map { Line(time: max(0, $0.time + offset), text: $0.text) }
            .enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    /// The line being sung at `time`, or nil before the first line and in
    /// gaps.
    func line(at time: Double) -> Line? {
        guard let i = index(at: time) else { return nil }
        return lines[i].text.isEmpty ? nil : lines[i]
    }

    /// The lines still to come after the one at `time`, gaps skipped, at most
    /// `count`. Before the first line this is the opening line: what the
    /// expanded lyrics show as "coming up" during an intro.
    func upcoming(at time: Double, count: Int) -> [Line] {
        guard count > 0 else { return [] }
        let start = index(at: time).map { $0 + 1 } ?? 0
        return Array(lines[start...].lazy.filter { !$0.text.isEmpty }.prefix(count))
    }

    /// Index of the last line stamped at or before `time`, gaps included.
    /// Binary search: this runs a few times a second.
    private func index(at time: Double) -> Int? {
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? lo - 1 : nil
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx` (also `:` before the fraction).
    private static func seconds(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0]), minutes >= 0,
              parts[0].allSatisfy(\.isNumber) else { return nil }
        let secondsPart = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsPart), seconds >= 0, seconds < 60,
              secondsPart.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(minutes) * 60 + seconds
    }

    private static func stripWordStamps(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\d+:\d+(?:[.:]\d+)?>"#, with: "", options: .regularExpression)
    }
}
