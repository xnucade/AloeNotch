// Tests for how headphone battery levels are worded.

func testHeadphoneBattery() {
    expect(HeadphoneBatteryReading(left: 80, right: 78).summary == "78%",
          "close buds show one number, the lower")
    expect(HeadphoneBatteryReading(left: 80, right: 40).summary == "L 80%  R 40%",
          "far-apart buds show both")
    expect(HeadphoneBatteryReading(left: 60, right: 0).summary == "60%",
          "a bud reporting 0 counts as missing")
    expect(HeadphoneBatteryReading(right: 55, caseLevel: 90).summary == "55%",
          "one bud out of the case")
    expect(HeadphoneBatteryReading(single: 42).summary == "42%",
          "over-ear headphones use the single level")
    expect(HeadphoneBatteryReading(left: 70, right: 70, single: 10).summary == "70%",
          "bud levels win over a single level")
    expect(HeadphoneBatteryReading(caseLevel: 90).isEmpty,
          "only a case level is nothing to show")
    expect(HeadphoneBatteryReading(left: 0, right: 0, single: 0).summary == nil,
          "all zeros is no reading")
    expect(HeadphoneBatteryReading(single: 140).summary == nil,
          "out-of-range values are ignored")
}
