import AppKit

/// A clipboard entry, and the rules for what the history keeps.
///
/// Split out of `ClipboardManager` because everything here is pure — no
/// pasteboard, no timer, no app — which is exactly what `scripts/run-tests.sh`
/// can compile and exercise directly. The invariants that matter (newest first,
/// no duplicates, hard caps on both rows and images) live here rather than
/// tangled into a polling loop where they can only be checked by hand.

/// The ordered history itself: pinned entries first, in the order they were
/// pinned, then everything else newest first.
struct ClipboardHistory: Equatable {
    /// How many unpinned entries to keep. Deep enough to cover "I copied over
    /// the thing I needed", shallow enough that the list stays scannable.
    static let capacity = 24

    /// Images are kept too, but sparingly — they are orders of magnitude larger
    /// than text, and an unbounded image history is a memory leak with a UI.
    /// Both a count and a byte budget: four small icons are nothing, four
    /// full-screen grabs are not.
    static let imageCapacity = 4
    static let imageByteBudget = 20 * 1024 * 1024

    /// Pins are for the handful of things you paste all day — an address, a
    /// snippet, a sign-off. More than a few and they push the history itself
    /// off the bottom of a four-row column.
    static let pinCapacity = 6
    /// At most half the image allowance can be pinned, so a fresh screenshot
    /// always has somewhere to go.
    static let pinnedImageCapacity = 2

    private(set) var pinned: [ClipItem] = []
    private(set) var recent: [ClipItem] = []

    var items: [ClipItem] { pinned + recent }
    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    mutating func insert(_ item: ClipItem) {
        // Copying a pinned entry again leaves it where it is — its place is
        // one the user chose — but takes the new copy's formatting, which is
        // the version they have just looked at.
        if let i = pinned.firstIndex(where: { $0.isSameContent(as: item) }) {
            pinned[i].formats = item.formats
            return
        }

        // Re-copying something already in the history moves it to the top
        // rather than adding a second copy of it.
        recent.removeAll { $0.isSameContent(as: item) }
        recent.insert(item, at: 0)
        enforceLimits()
    }

    func isPinned(_ item: ClipItem) -> Bool { pinned.contains { $0.id == item.id } }

    func canPin(_ item: ClipItem) -> Bool {
        guard recent.contains(where: { $0.id == item.id }),
              pinned.count < Self.pinCapacity else { return false }
        return !item.isImage || pinned.filter(\.isImage).count < Self.pinnedImageCapacity
    }

    mutating func pin(_ item: ClipItem) {
        guard canPin(item), let i = recent.firstIndex(where: { $0.id == item.id }) else { return }
        pinned.append(recent.remove(at: i))
    }

    /// Back to the top of the history rather than to where its date would
    /// put it: an old entry slotted back by date could fall straight off the
    /// end, and unpinning would quietly mean deleting.
    mutating func unpin(_ item: ClipItem) {
        guard let i = pinned.firstIndex(where: { $0.id == item.id }) else { return }
        recent.insert(pinned.remove(at: i), at: 0)
        enforceLimits()
    }

    mutating func remove(_ item: ClipItem) {
        pinned.removeAll { $0.id == item.id }
        recent.removeAll { $0.id == item.id }
    }

    /// Everything, pins included. "Forget" has to mean forget.
    mutating func removeAll() {
        pinned.removeAll()
        recent.removeAll()
    }

    /// The entries a search shows, in the same order as the full list.
    func items(matching query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { $0.matches(q) }
    }

    private mutating func enforceLimits() {
        if recent.count > Self.capacity {
            recent.removeLast(recent.count - Self.capacity)
        }
        // Trim the oldest unpinned images independently of the overall cap,
        // so a burst of screenshots can't sit in memory just because it is
        // recent. Pinned images count against the allowance but are never
        // the ones dropped.
        var count = pinned.filter(\.isImage).count
        var bytes = pinned.reduce(0) { $0 + $1.imageBytes }
        recent.removeAll { item in
            guard item.isImage else { return false }
            let fits = count + 1 <= Self.imageCapacity && bytes + item.imageBytes <= Self.imageByteBudget
            if fits {
                count += 1
                bytes += item.imageBytes
            }
            return !fits
        }
    }
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
    /// Richer copies of a text entry — RTF, HTML — keyed by pasteboard type,
    /// so copying it back keeps the bold and the links. In memory only, like
    /// everything else here.
    var formats: [String: Data] = [:]
    /// The original's size in pixels. The thumbnail's own size is whatever it
    /// was scaled to, which is not what anyone wants to read.
    var pixelSize: CGSize?

    var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    var imageBytes: Int {
        if case .image(_, let data) = kind { return data.count }
        return 0
    }

    var hasFormatting: Bool { !formats.isEmpty }

    /// Case- and accent-insensitive, the way Finder and Spotlight search. Text
    /// matches on its full contents, not the one-line preview; files on their
    /// names. Images have nothing to search but are found by "image".
    func matches(_ query: String) -> Bool {
        switch kind {
        case .text(let s):
            return s.localizedStandardContains(query)
        case .files(let urls):
            return urls.contains { $0.lastPathComponent.localizedStandardContains(query) }
        case .image:
            return String(localized: "Image").localizedStandardContains(query)
        }
    }

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
            let px = pixelSize ?? thumb.size
            // Strings, not Ints: a localized Int gains grouping, and
            // "3,024×1,964" reads as four numbers.
            let (w, h) = (String(Int(px.width)), String(Int(px.height)))
            return String(localized: "Image \(w)×\(h)")
        case .files(let urls):
            return urls.count == 1
                ? urls[0].lastPathComponent
                : "\(urls.count) files"
        }
    }

    /// What a row shows while it might be on someone else's screen: the kind
    /// of thing, never the thing. The count is dropped too — "8 chars" next to
    /// a login form says more than it should.
    var redactedPreview: String {
        switch kind {
        case .text(let s):  s.looksLikeURL ? "Link" : "Text"
        case .image:        "Image"
        case .files(let u): u.count == 1 ? "File" : "\(u.count) files"
        }
    }

    /// Right-hand label — what kind of thing this is, at a glance.
    var detail: String {
        switch kind {
        case .text(let s):
            let n = s.count
            return n == 1 ? String(localized: "1 char") : String(localized: "\(n) chars")
        case .image:  return String(localized: "Image")
        case .files:  return String(localized: "Files")
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
