// Tests for LRC parsing and line lookup.

func testSyncedLyrics() {
    let lrc = """
    [ar:Someone]
    [ti:Something]
    [00:01.50]First line
    [00:04.2]Second line
    [00:08.000]
    [00:10.00][00:20.00]Chorus
    [00:15:50]Colon fraction
    not a lyric
    """
    guard let lyrics = SyncedLyrics(lrc: lrc) else {
        expect(false, "LRC parses"); return
    }
    expect(lyrics.lines.count == 6, "one line per stamp, metadata dropped")
    expect(lyrics.line(at: 0) == nil, "nothing before the first line")
    expect(lyrics.line(at: 1.5)?.text == "First line", "a line starts on its stamp")
    expect(lyrics.line(at: 4.19)?.text == "First line", "and holds until the next")
    expect(lyrics.line(at: 4.2)?.text == "Second line", "two-digit fractions")
    expect(lyrics.line(at: 9) == nil, "an empty line is an instrumental gap")
    expect(lyrics.line(at: 12)?.text == "Chorus", "a line with several stamps")
    expect(lyrics.line(at: 15.5)?.text == "Colon fraction", "mm:ss:xx stamps")
    expect(lyrics.line(at: 25)?.text == "Chorus", "and again at its later stamp")

    let shifted = SyncedLyrics(lrc: "[offset:+500]\n[00:02.00]Early")
    expect(shifted?.line(at: 1.5)?.text == "Early", "a positive offset brings lines sooner")

    let words = SyncedLyrics(lrc: "[00:01.00]<00:01.00>Word <00:01.50>by word")
    expect(words?.line(at: 2)?.text == "Word by word", "word-level stamps are stripped")

    expect(SyncedLyrics(lrc: "Plain lyrics\nno stamps") == nil, "unsynced text is not lyrics")
    expect(SyncedLyrics(lrc: "[00:01.00]\n[00:02.00]") == nil, "all-gap lyrics are not lyrics")
    expect(SyncedLyrics(lrc: "[99:99.00]Bad") == nil, "out-of-range stamps are ignored")
}
