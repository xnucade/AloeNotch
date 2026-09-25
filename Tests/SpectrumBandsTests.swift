// Tests for the equalizer's band analysis, using synthetic tones.

import Foundation

func testSpectrumBands() {
    let rate = 48_000.0
    func tone(_ hz: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<SpectrumBands.blockSize).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }
    func loudest(_ levels: [Float]) -> Int { levels.indices.max { levels[$0] < levels[$1] }! }

    var bands = SpectrumBands(sampleRate: rate)
    defer { bands.destroy() }

    let silence = bands.process([Float](repeating: 0, count: SpectrumBands.blockSize))
    expect(silence.count == 4, "four bands, one per bar")
    expect(silence.allSatisfy { $0 == 0 }, "silence is empty bars")

    for (hz, band) in [(100.0, 0), (500.0, 1), (2000.0, 2), (8000.0, 3)] {
        var fresh = SpectrumBands(sampleRate: rate)
        let levels = fresh.process(tone(hz))
        expect(loudest(levels) == band, "a \(Int(hz)) Hz tone lights band \(band)")
        expect(levels[band] > 0.7, "a loud \(Int(hz)) Hz tone nearly fills its bar")
        fresh.destroy()
    }

    let loud = bands.process(tone(100))[0]
    let after = bands.process([Float](repeating: 0, count: SpectrumBands.blockSize))[0]
    expect(after > 0 && after < loud, "bars fall gradually, not at once")

    var quiet = SpectrumBands(sampleRate: rate)
    expect(quiet.process(tone(100, amplitude: 0.001))[0] < 0.2, "a whisper barely moves a bar")
    quiet.destroy()
}
