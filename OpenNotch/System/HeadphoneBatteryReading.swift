import Foundation

/// Battery levels as a Bluetooth headset reports them, and how the notch
/// words them. Pure, so the wording is tested without a pair of AirPods.
///
/// Headsets report 0 for "unknown" as well as for a component that isn't
/// there (a bud in the case, no case at all), so 0 is treated as missing.
struct HeadphoneBatteryReading: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Over-ear headphones and single-battery earbuds report only this.
    var single: Int?

    init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) {
        func known(_ v: Int?) -> Int? { v.flatMap { (1...100).contains($0) ? $0 : nil } }
        self.left = known(left)
        self.right = known(right)
        self.caseLevel = known(caseLevel)
        self.single = known(single)
    }

    var isEmpty: Bool { left == nil && right == nil && single == nil }

    /// Short enough for the strip's trailing slot. Buds within a few points
    /// of each other are one number — the lower, since that one runs out
    /// first; further apart, both.
    var summary: String? {
        switch (left, right) {
        case let (l?, r?):
            return abs(l - r) <= 5 ? "\(min(l, r))%" : "L \(l)%  R \(r)%"
        case let (l?, nil): return "\(l)%"
        case let (nil, r?): return "\(r)%"
        case (nil, nil):    return single.map { "\($0)%" }
        }
    }
}
