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
}
