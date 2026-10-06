import Foundation
import Accelerate

/// Turns blocks of audio into a few bar heights: an FFT, the energy in each
/// frequency band, decibels mapped onto 0…1, then a fast rise and a slower
/// fall so the bars read as music rather than flicker.
///
/// No Core Audio here — samples in, levels out — so it's tested from the
/// shell with synthetic tones.
struct SpectrumBands {
    static let blockSize = 1024

    /// Band edges in Hz. Four bands, one per bar: lows, low-mids, high-mids,
    /// highs — spaced roughly evenly on a log scale, the way pitch is heard.
    static let edges: [Double] = [40, 200, 900, 3500, 14000]

    /// Quieter than this is an empty bar, this much or louder a full one.
    private static let floorDB: Float = -60
    private static let ceilingDB: Float = -12

    private(set) var levels: [Float]
    private let bins: [Range<Int>]
    private let setup: FFTSetup
    private let log2n: vDSP_Length
    private let window: [Float]

    init(sampleRate: Double) {
        let n = Self.blockSize
        log2n = vDSP_Length(log2(Double(n)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: n, isHalfWindow: false)
        let hzPerBin = sampleRate / Double(n)
        let nyquistBin = n / 2
        bins = zip(Self.edges, Self.edges.dropFirst()).map { lo, hi in
            let a = min(nyquistBin - 1, max(1, Int((lo / hzPerBin).rounded())))
            let b = min(nyquistBin, max(a + 1, Int((hi / hzPerBin).rounded())))
            return a..<b
        }
        levels = Array(repeating: 0, count: bins.count)
    }

    /// Feeds one block of exactly `blockSize` mono samples and returns the
    /// smoothed levels.
    mutating func process(_ samples: [Float]) -> [Float] {
        precondition(samples.count == Self.blockSize)
        let n = Self.blockSize
        let windowed = vDSP.multiply(samples, window)

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Bin 0 packs DC and Nyquist together; neither is in a band.
                split.imagp[0] = 0
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }

        // zrip's output is scaled by 2, and the Hann window halves amplitude;
        // this makes a full-scale sine land near 0 dB in its band.
        let scale = 1 / Float(n * n)
        for (i, range) in bins.enumerated() {
            let energy = power[range].reduce(0, +) * scale
            let db = 10 * log10(max(energy, 1e-12))
            let target = min(1, max(0, (db - Self.floorDB) / (Self.ceilingDB - Self.floorDB)))
            // Rise at once, fall over a few blocks.
            levels[i] = target > levels[i] ? target : levels[i] + (target - levels[i]) * 0.25
        }
        return levels
    }

    func destroy() { vDSP_destroy_fftsetup(setup) }
}
