// Tests for what the clipboard history keeps, drops and reorders.
//
// The pasteboard polling itself is not covered here — it needs a real
// NSPasteboard, which would mean clobbering the clipboard of whoever runs the
// suite. Everything with an invariant worth defending was split into
// ClipboardHistory precisely so it could be tested without that.

import AppKit

private func text(_ s: String) -> ClipItem { ClipItem(kind: .text(s)) }
private func image() -> ClipItem {
    ClipItem(kind: .image(NSImage(size: NSSize(width: 8, height: 8)),
                          Data(UUID().uuidString.utf8)))
}

func testClipboardHistory() {
    var h = ClipboardHistory()
    expect(h.isEmpty, "a new history is empty")

    h.insert(text("one"))
    h.insert(text("two"))
    expect(h.items.count == 2, "entries accumulate")
    expect(h.items.first?.preview == "two", "newest first — the list is read from the top")

    // Re-copying something you already copied is the single most common thing a
    // clipboard history has to handle well.
    h.insert(text("one"))
    expect(h.items.count == 2, "re-copying does not duplicate")
    expect(h.items.first?.preview == "one", "re-copying promotes to the top")

    // Capacity is a hard bound. Without it the history is a memory leak that
    // grows for as long as the app runs.
    var big = ClipboardHistory()
    for i in 0..<(ClipboardHistory.capacity + 15) { big.insert(text("item-\(i)")) }
    expect(big.items.count == ClipboardHistory.capacity,
           "history is capped at \(ClipboardHistory.capacity)")
    expect(big.items.first?.preview == "item-\(ClipboardHistory.capacity + 14)",
           "the cap drops the oldest, not the newest")
    expect(!big.items.contains { $0.preview == "item-0" }, "the oldest entry is gone")

    // Images are capped separately and more tightly: a burst of screenshots
    // must not fill memory just because it is recent.
    var mixed = ClipboardHistory()
    for _ in 0..<(ClipboardHistory.imageCapacity + 6) { mixed.insert(image()) }
    let imageCount = mixed.items.filter { if case .image = $0.kind { return true } else { return false } }.count
    expect(imageCount == ClipboardHistory.imageCapacity,
           "at most \(ClipboardHistory.imageCapacity) images are kept")

    // Trimming images must not take text with it.
    var both = ClipboardHistory()
    for i in 0..<6 { both.insert(text("t\(i)")); both.insert(image()) }
    let texts = both.items.filter { if case .text = $0.kind { return true } else { return false } }.count
    expect(texts == 6, "trimming images leaves text alone")

    h.remove(h.items[0])
    expect(h.items.count == 1, "an entry can be removed")
    h.removeAll()
    expect(h.isEmpty, "clearing empties the history")
}

private func image(bytes: Int, fill: UInt8) -> ClipItem {
    ClipItem(kind: .image(NSImage(size: NSSize(width: 8, height: 8)),
                          Data(repeating: fill, count: bytes)))
}

func testClipboardPins() {
    var h = ClipboardHistory()
    h.insert(text("address"))
    h.insert(text("b"))
    let address = h.items[1]

    h.pin(address)
    expect(h.isPinned(address), "an entry can be pinned")
    expect(h.items.first?.id == address.id, "pinned entries list first")
    expect(h.pinned.count == 1 && h.recent.count == 1, "pinning moves, it doesn't copy")

    // A pin survives any amount of copying after it.
    for i in 0..<(ClipboardHistory.capacity + 5) { h.insert(text("flood-\(i)")) }
    expect(h.isPinned(address), "pins are never evicted by the capacity cap")
    expect(h.recent.count == ClipboardHistory.capacity, "the cap still holds for the rest")

    // Copying a pinned entry again doesn't duplicate it or move it.
    var rich = text("address")
    rich.formats = ["public.rtf": Data("{\\rtf1}".utf8)]
    h.insert(rich)
    expect(h.items.filter { $0.preview == "address" }.count == 1, "re-copying a pin doesn't duplicate it")
    expect(h.pinned.first?.id == address.id, "re-copying a pin keeps it in place")
    expect(h.pinned.first?.hasFormatting == true, "but picks up the new copy's formatting")

    // Unpinning returns it to the top of the history, where it can't be
    // silently evicted.
    h.unpin(address)
    expect(!h.isPinned(address) && h.recent.first?.id == address.id, "unpinning returns it to the top")
    expect(h.recent.count == ClipboardHistory.capacity, "and the cap is enforced again")

    // Capacity.
    var full = ClipboardHistory()
    for i in 0..<(ClipboardHistory.pinCapacity + 2) { full.insert(text("p\(i)")) }
    for item in full.recent { full.pin(item) }
    expect(full.pinned.count == ClipboardHistory.pinCapacity, "pins are capped")
    expect(!full.canPin(full.recent[0]), "and refused past the cap")

    // Pinned images are limited, so fresh images always have room.
    var imgs = ClipboardHistory()
    for i in 0..<3 { imgs.insert(image(bytes: 10, fill: UInt8(i))) }
    for item in imgs.recent { imgs.pin(item) }
    expect(imgs.pinned.count == ClipboardHistory.pinnedImageCapacity, "only so many images can be pinned")
    for i in 10..<20 { imgs.insert(image(bytes: 10, fill: UInt8(i))) }
    expect(imgs.items.filter(\.isImage).count == ClipboardHistory.imageCapacity,
           "pinned images count against the image allowance")
    expect(imgs.pinned.count == ClipboardHistory.pinnedImageCapacity, "but are never the ones dropped")

    // Clearing forgets pins too.
    h.pin(h.recent[0])
    h.removeAll()
    expect(h.isEmpty, "clearing forgets pinned entries as well")

    // Removing works on either list.
    var r = ClipboardHistory()
    r.insert(text("x")); r.insert(text("y"))
    r.pin(r.recent[0])
    r.remove(r.pinned[0])
    expect(r.items.count == 1 && r.pinned.isEmpty, "a pinned entry can be removed")
}

func testClipboardImageBudget() {
    // Three 8 MB images fit the count cap but not the byte budget.
    var h = ClipboardHistory()
    let mb = 1024 * 1024
    for i in 0..<3 { h.insert(image(bytes: 8 * mb, fill: UInt8(i))) }
    let bytes = h.items.reduce(0) { $0 + $1.imageBytes }
    expect(bytes <= ClipboardHistory.imageByteBudget, "images stay within the byte budget")
    expect(h.items.filter(\.isImage).count == 2, "the oldest image is the one dropped")
    expect(h.items.first?.imageBytes == 8 * mb, "the newest image is kept")
}

func testClipboardSearch() {
    var h = ClipboardHistory()
    h.insert(text("Café au lait"))
    h.insert(ClipItem(kind: .files([URL(fileURLWithPath: "/tmp/Quarterly Report.pdf")])))
    h.insert(text("line one\nthe needle is on line two"))
    h.insert(image())

    expect(h.items(matching: "").count == 4, "an empty search shows everything")
    expect(h.items(matching: "   ").count == 4, "whitespace alone is an empty search")
    expect(h.items(matching: "cafe").count == 1, "search ignores accents")
    expect(h.items(matching: "CAFÉ").count == 1, "and case")
    expect(h.items(matching: "needle").count == 1, "text matches beyond its first line")
    expect(h.items(matching: "report").count == 1, "files match on their names")
    expect(h.items(matching: "tmp").isEmpty, "but not on their folder")
    expect(h.items(matching: "image").count == 1, "images are found by kind")
    expect(h.items(matching: "zzz").isEmpty, "no match shows nothing")

    h.pin(h.recent[3])
    expect(h.items(matching: "a").first?.preview == "Café au lait", "search keeps pinned entries first")
}

func testClipItemPresentation() {
    // A copied code block is mostly newlines and indentation. Showing it raw
    // turns a one-line row into a ragged mess.
    expect(text("func a() {\n    return 1\n}").preview == "func a() { return 1 }",
           "multi-line text collapses to one line")
    expect(text("  spaced   out  ").preview == "spaced out",
           "runs of whitespace collapse")

    // The glyph is the only thing distinguishing rows at a glance.
    expect(text("https://example.com/thing").symbol == "link", "URLs get a link glyph")
    expect(text("just some words").symbol == "text.alignleft", "prose gets a text glyph")
    expect(text("https://a").symbol == "text.alignleft",
           "a scheme with no dotted host is prose, not a link")
    expect(text("http://localhost:3000").symbol == "link", "localhost still counts")
    expect(text("ftp://example.com").symbol == "text.alignleft",
           "only http(s) gets the link glyph")
    expect(text("https://example.com and more").symbol == "text.alignleft",
           "a sentence containing a URL is still prose")
    expect(image().symbol == "photo", "images get an image glyph")

    let one = ClipItem(kind: .files([URL(fileURLWithPath: "/tmp/report.pdf")]))
    expect(one.preview == "report.pdf", "a single file shows its name, not its path")
    expect(one.symbol == "doc", "one file gets the single-document glyph")

    let many = ClipItem(kind: .files([URL(fileURLWithPath: "/tmp/a"),
                                      URL(fileURLWithPath: "/tmp/b")]))
    expect(many.preview == "2 files", "several files are counted rather than listed")
    expect(many.symbol == "doc.on.doc", "several files get the stacked glyph")

    expect(text("abc").detail == "3 chars", "text reports its length")
    expect(text("a").detail == "1 char", "one character is singular")

    // Redacted rows, for while the screen may be shared.
    expect(text("hunter2").redactedPreview == "Text", "redacted text shows only its kind")
    expect(!text("hunter2").redactedPreview.contains("7"), "and not even its length")
    expect(text("https://example.com/reset?token=abc").redactedPreview == "Link", "links say link")
    expect(one.redactedPreview == "File", "a file's name is hidden")
    expect(many.redactedPreview == "2 files", "a count of files gives nothing away")
    expect(image().redactedPreview == "Image", "images say image")

    var shot = image()
    shot.pixelSize = CGSize(width: 3024, height: 1964)
    expect(shot.preview == "Image 3024×1964", "an image reports the original's size, not the thumbnail's")
}
