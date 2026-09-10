import AppKit

/// A clipboard entry, and the rules for what the history keeps.
///
/// Split out of `ClipboardManager` because everything here is pure — no
/// pasteboard, no timer, no app — which is exactly what `scripts/run-tests.sh`
/// can compile and exercise directly. The invariants that matter (newest first,
/// no duplicates, hard caps on both rows and images) live here rather than
/// tangled into a polling loop where they can only be checked by hand.

/// The ordered history itself.
struct ClipboardHistory: Equatable {
    /// How many entries to keep. Deep enough to cover "I copied over the thing
    /// I needed", shallow enough that the list stays scannable.
    static let capacity = 24

    /// Images are kept too, but sparingly — they are orders of magnitude larger
    /// than text, and an unbounded image history is a memory leak with a UI.
    static let imageCapacity = 4

    private(set) var items: [ClipItem] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func insert(_ item: ClipItem) {
        // Re-copying something already in the history moves it to the top
        // rather than adding a second copy of it.
        items.removeAll { $0.isSameContent(as: item) }
        items.insert(item, at: 0)

        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        // Trim the oldest images independently of the overall cap, so a burst
        // of screenshots can't sit in memory just because it is recent.
        var imagesSeen = 0
        items.removeAll { item in
            guard case .image = item.kind else { return false }
            imagesSeen += 1
            return imagesSeen > Self.imageCapacity
        }
    }

    mutating func remove(_ item: ClipItem) { items.removeAll { $0.id == item.id } }
    mutating func removeAll() { items.removeAll() }
}

struct ClipItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        /// Display thumbnail, plus the PNG bytes to put back on the pasteboard.
        case image(NSImage, Data)
        case files([URL])

        static func == (a: Kind, b: Kind) -> Bool {
            switch (a, b) {
            case let (.text(x), .text(y)):          x == y
            case let (.image(_, x), .image(_, y)):  x == y
            case let (.files(x), .files(y)):        x == y
            default:                                false
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let date = Date()

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id }

    func isSameContent(as other: ClipItem) -> Bool { kind == other.kind }

    var symbol: String {
        switch kind {
        case .text(let s): s.looksLikeURL ? "link" : "text.alignleft"
        case .image:       "photo"
        case .files(let u): u.count > 1 ? "doc.on.doc" : "doc"
        }
    }

    /// One line, whitespace collapsed. A copied code block is mostly newlines
    /// and indentation, and showing those raw turns the row into a ragged mess.
    var preview: String {
        switch kind {
        case .text(let s):
            return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .image(let thumb, _):
            let px = thumb.size
            return "Image \(Int(px.width))×\(Int(px.height))"
        case .files(let urls):
            return urls.count == 1
                ? urls[0].lastPathComponent
                : "\(urls.count) files"
        }
    }

    /// Right-hand label — what kind of thing this is, at a glance.
    var detail: String {
        switch kind {
        case .text(let s):
            let n = s.count
            return n == 1 ? "1 char" : "\(n) chars"
        case .image:  return "Image"
        case .files:  return "Files"
        }
    }
}

private extension String {
    /// Whether to draw this row with a link glyph rather than a text one.
    ///
    /// A scheme alone is not enough: `https://a` parses as a URL but is far more
    /// likely to be prose someone copied mid-sentence, and a wrong glyph is
    /// worse than a generic one. Requiring a dotted host (or localhost) is the
    /// cheap heuristic that gets the real cases right.
    var looksLikeURL: Bool {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" ") else { return false }
        let host: Substring
        if t.hasPrefix("https://")     { host = t.dropFirst(8) }
        else if t.hasPrefix("http://") { host = t.dropFirst(7) }
        else                           { return false }
        return host.contains(".") || host.hasPrefix("localhost")
    }
}
