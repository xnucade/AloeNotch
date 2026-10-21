import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// Live band levels of whatever the Mac is playing, for the equalizer glyph.
/// Opt-in, and only running while a glyph is on screen and music is playing.
///
/// Uses a Core Audio process tap (macOS 14.2+): a private, mono mixdown of
/// all system output, attached to a private aggregate device whose IO block
/// hands us samples. The audio is measured and dropped — four numbers leave
/// the IO queue, never a sample.
///
/// Permission is macOS's "system audio recording", asked for on first start.
/// There is no API to read it back, and a denied tap doesn't fail — it
/// delivers silence. So `levels` goes nil after a couple of seconds of
/// digital silence, and the glyph falls back to its loop.
///
/// Each group of state below is touched from one queue only, as marked,
/// which is what makes the `@unchecked Sendable` honest.
final class AudioLevels: ObservableObject, @unchecked Sendable {
    static let shared = AudioLevels()

    /// Nil means "not live": off, starting, denied, or silent.
    @Published private(set) var levels: [Float]?

    private let control = DispatchQueue(label: "com.kadeslab.AloeNotch.audiolevels.control")
    private let io = DispatchQueue(label: "com.kadeslab.AloeNotch.audiolevels.io", qos: .userInteractive)

    // Main thread.
    private var demand = 0
    private var pendingStop: DispatchWorkItem?

    // Control queue.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    // IO queue. One block is gathered in place and analysed when full, so
    // the audio path allocates nothing per callback.
    private var bands: SpectrumBands?
    private var block = [Float](repeating: 0, count: SpectrumBands.blockSize)
    private var filled = 0
    private var blockHasSound = false
    private var silentBlocks = 0
    private var lastPublish = Date.distantPast
    /// Last levels sent to the main thread, so an unchanged frame isn't sent.
    private var lastSent: [Float]?

    /// Called by each glyph that wants live levels; balanced by `release()`.
    @MainActor func acquire() {
        demand += 1
        pendingStop?.cancel()
        pendingStop = nil
        if demand == 1 { control.async { self.start() } }
    }

    @MainActor func release() {
        demand = max(0, demand - 1)
        guard demand == 0 else { return }
        // A short grace, so a glyph being replaced by another (a view
        // identity change mid-transition) doesn't rebuild the tap.
        let stop = DispatchWorkItem { [weak self] in
            guard let self, self.demand == 0 else { return }
            self.levels = nil
            self.control.async { self.stop() }
        }
        pendingStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: stop)
    }

    // MARK: - Tap lifecycle (control queue)

    private func start() {
        guard procID == nil else { return }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "AloeNotch levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return teardown() }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &format) == noErr,
              format.mSampleRate > 0 else { return teardown() }

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AloeNotch levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        // Clocked by the real output device, as Apple's sample does.
        if let output = Self.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr
        else { return teardown() }

        let rate = format.mSampleRate
        io.sync {
            bands = SpectrumBands(sampleRate: rate)
            filled = 0
            blockHasSound = false
            silentBlocks = 0
            lastSent = nil
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, io) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr
        else { return teardown() }
    }

    private func stop() { teardown() }

    private func teardown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        io.async {
            self.bands?.destroy()
            self.bands = nil
        }
    }

    // MARK: - Samples (IO queue)

    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        guard bands != nil else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(1, Int(first.mNumberChannels))
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let samples = data.assumingMemoryBound(to: Float.self)

        // Channel 0 of an interleaved buffer; the tap is mono, so usually all.
        let n = SpectrumBands.blockSize
        var i = 0
        while i < count {
            let take = min(count - i, n - filled)
            var sound = blockHasSound
            block.withUnsafeMutableBufferPointer { dst in
                for j in 0..<take {
                    let sample = samples[(i + j) * channels]
                    dst[filled + j] = sample
                    if sample != 0 { sound = true }
                }
            }
            blockHasSound = sound
            filled += take
            i += take
            if filled == n {
                analyze()
                filled = 0
                blockHasSound = false
            }
        }
    }

    private func analyze() {
        guard bands != nil else { return }
        let levels = block.withUnsafeBufferPointer { bands!.process($0) }

        silentBlocks = blockHasSound ? 0 : silentBlocks + 1
        // ~2 s of exact zeros: denied, or nothing actually sounding.
        let live = silentBlocks < 90

        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 1.0 / 30 else { return }
        let next = live ? SpectrumBands.quantized(levels) : nil
        // Most frames of a held note or a fade round to what is already on
        // screen; those cost the main thread nothing.
        guard next != lastSent else { return }
        lastPublish = now
        lastSent = next
        DispatchQueue.main.async {
            guard self.demand > 0 else { return }
            if self.levels != next { self.levels = next }
        }
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
