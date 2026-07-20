import Foundation
import CoreAudio
import AudioToolbox

/// Watches the default output device's volume and mute state through CoreAudio
/// and reports changes. No special permission is required.
///
/// The first reading is swallowed (`primed`) so launching the app doesn't flash
/// a HUD for a level the user didn't just change.
final class VolumeMonitor {
    /// Called on the main queue with (level 0…1, muted) when the user changes it.
    var onChange: ((Float, Bool) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var primed = false
    private var running = false

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !running else { return }
        running = true
        attachToDefaultDevice()

        // Re-attach when the user switches output (headphones, AirPlay, …).
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main
        ) { [weak self] _, _ in
            guard let self, self.running else { return }
            self.detachListeners()
            self.primed = false          // don't fire a HUD just for switching
            self.attachToDefaultDevice()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        detachListeners()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main
        ) { _, _ in }
    }

    // MARK: - Wiring

    private func attachToDefaultDevice() {
        guard let id = currentDefaultOutputDevice() else { return }
        deviceID = id

        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.report()
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, .main, handler)
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, .main, handler)

        report()   // primes the baseline without emitting
    }

    private func detachListeners() {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        let noop: AudioObjectPropertyListenerBlock = { _, _ in }
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, .main, noop)
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, .main, noop)
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func report() {
        let level = currentVolume()
        let muted = currentMute()
        guard primed else { primed = true; return }
        onChange?(level, muted)
    }

    // MARK: - Control (used when we intercept the volume keys ourselves)

    func level() -> Float { currentVolume() }
    func muted() -> Bool { currentMute() }

    func setLevel(_ newValue: Float) {
        var value = Float32(min(1, max(0, newValue)))
        AudioObjectSetPropertyData(
            deviceID, &volumeAddress, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &value
        )
    }

    func setMuted(_ newValue: Bool) {
        var value: UInt32 = newValue ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID, &muteAddress, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value
        )
    }

    // MARK: - Reads

    private func currentDefaultOutputDevice() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &id
        )
        return status == noErr && id != AudioObjectID(kAudioObjectUnknown) ? id : nil
    }

    private func currentVolume() -> Float {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value)
        return status == noErr ? min(1, max(0, value)) : 0
    }

    private func currentMute() -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value)
        return status == noErr && value == 1
    }
}
