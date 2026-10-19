// Tests for what the Notes module writes to disk, against a temporary
// directory so the real note is never touched.

import Foundation

func testNoteFile() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("aloenotch-notes-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = NoteFile(url: dir.appendingPathComponent("AloeNotch/Notes.txt"))
    let fm = FileManager.default

    expect(file.load() == "", "no file reads as an empty note")

    // Round trip, folder created on the way.
    do {
        try file.save("milk\neggs ☕️")
        expect(file.load() == "milk\neggs ☕️", "a saved note reads back exactly")
        let perms = (try fm.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber)?.intValue
        expect(perms == 0o600, "the note is readable by its owner only")
    } catch {
        expect(false, "saving a note threw: \(error)")
    }

    // Clearing removes the file rather than leaving an empty one.
    do {
        try file.save("")
        expect(!fm.fileExists(atPath: file.url.path), "an empty note deletes the file")
        try file.save("")
        expect(true, "clearing an already-missing note is fine")
    } catch {
        expect(false, "clearing a note threw: \(error)")
    }

    // The ceiling.
    let long = String(repeating: "a", count: NoteFile.limit + 50)
    expect(NoteFile.clamp(long).count == NoteFile.limit, "text past the limit is cut to the limit")
    expect(NoteFile.clamp("short") == "short", "text under the limit is untouched")
    do {
        try file.save(long)
        expect(file.load().count == NoteFile.limit, "an over-long note is stored at the limit")
    } catch {
        expect(false, "saving a long note threw: \(error)")
    }
}
