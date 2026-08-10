import Foundation

/// Comparison for the `MAJOR.MINOR.PATCH` strings used for releases.
///
/// Exists because the obvious approach is wrong in a way that stays hidden for
/// a long time: comparing versions as strings puts "0.10.0" *below* "0.9.0",
/// since "1" sorts before "9". Nothing goes wrong until the tenth minor
/// release, by which point the code looks well-tested by sheer age.
///
/// Free of SwiftUI so it can be compiled and tested on its own
/// (see `scripts/run-tests.sh`).
enum SemanticVersion {
    /// Components, with missing ones treated as zero, so "1.2" == "1.2.0".
    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// `true` when `a` is the same as, or older than, `b`.
    static func isAtOrBelow(_ a: String, _ b: String) -> Bool {
        compare(a, b) <= 0
    }

    /// -1, 0 or 1, in the manner of a C comparator.
    static func compare(_ a: String, _ b: String) -> Int {
        let l = components(a), r = components(b)
        for i in 0..<max(l.count, r.count) {
            let x = i < l.count ? l[i] : 0
            let y = i < r.count ? r[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
