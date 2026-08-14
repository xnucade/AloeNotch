// Minimal test harness.
//
// Deliberately not XCTest. The logic under test is pure and lives in two small
// SwiftUI-free files, so it can be compiled directly — which means the tests
// run in about a second from a shell, with no Xcode target, no scheme and no
// pbxproj surgery to keep in sync. If the suite ever needs to touch views or
// the view model, that trade stops paying and a real XCTest target is the
// right answer.

import Foundation

var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ description: String) {
    checks += 1
    if !condition { failures.append(description) }
}

testPanelState()
testSemanticVersion()
testUpdateComparison()

if failures.isEmpty {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures.count) of \(checks) checks failed:\n")
    for f in failures { print("  - \(f)") }
    exit(1)
}
