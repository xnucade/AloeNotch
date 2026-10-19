import Foundation

/// The Notes module's one file on disk, and the only user data AloeNotch
/// writes there.
///
/// Plain text in Application Support, readable by its owner alone. Nothing
/// syncs it and nothing sends it anywhere. Clearing the note removes the file
/// rather than leaving an empty one behind, so "I deleted my notes" is true on
/// disk too.
///
/// Split from `NotesModel` so the rules can be tested against a temporary
/// directory without touching the real note.
struct NoteFile {
    /// Plenty for a scratchpad, and a ceiling on what one stray paste can
    /// make the panel lay out on every keystroke.
    static let limit = 20_000

    let url: URL

    /// `~/Library/Application Support/AloeNotch/Notes.txt`, beside the
    /// diagnostics folder.
    static var standard: NoteFile? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { NoteFile(url: $0.appendingPathComponent("AloeNotch/Notes.txt")) }
    }

    func load() -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return Self.clamp(String(decoding: data, as: UTF8.self))
    }

    /// Atomic, so a crash mid-write leaves the previous note rather than half
    /// of this one; owner-only, so other accounts on the Mac can't read it.
    func save(_ text: String) throws {
        let fm = FileManager.default
        guard !text.isEmpty else {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try Data(Self.clamp(text).utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clamp(_ text: String) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }
}
