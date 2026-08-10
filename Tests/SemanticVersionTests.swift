// Tests for release-version comparison.

func testSemanticVersion() {
    // The case that motivates having this at all. As strings, "0.10.0" sorts
    // below "0.9.0" because "1" < "9" — so a naive implementation passes every
    // test for nine minor releases and then silently stops offering release
    // notes.
    expect(SemanticVersion.compare("0.10.0", "0.9.0") == 1,
           "0.10.0 is newer than 0.9.0")
    expect(SemanticVersion.compare("1.0.0", "0.99.99") == 1,
           "major beats minor and patch")
    expect(SemanticVersion.compare("0.8.10", "0.8.9") == 1,
           "patch compares numerically too")

    // Ordering basics.
    expect(SemanticVersion.compare("0.8.0", "0.8.1") == -1, "older is -1")
    expect(SemanticVersion.compare("0.8.1", "0.8.1") == 0, "equal is 0")

    // Missing components are zero, so these are the same version.
    expect(SemanticVersion.compare("1.2", "1.2.0") == 0, "1.2 == 1.2.0")
    expect(SemanticVersion.compare("1", "1.0.0") == 0, "1 == 1.0.0")

    // What the what's-new lookup actually asks.
    expect(SemanticVersion.isAtOrBelow("0.8.0", "0.8.1"),
           "0.8.0 notes show on 0.8.1 — a patch with no notes of its own must "
           + "not hide the previous release's")
    expect(SemanticVersion.isAtOrBelow("0.8.0", "0.8.0"), "same version qualifies")
    expect(!SemanticVersion.isAtOrBelow("0.9.0", "0.8.1"),
           "notes for an unreleased version must not appear")

    // Garbage should not crash or throw; unparseable components read as zero.
    expect(SemanticVersion.compare("banana", "0.0.0") == 0,
           "unparseable degrades to zero rather than trapping")
}
