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

    // CoreAudio removes a listener only when handed the very block it was
    // added with, so each is made once and kept. Removing with a fresh no-op
    // block, as this used to, quietly removed nothing: every output switch
    // left the old device's listeners firing, and stop() never stopped.
    private lazy var deviceHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.report()
    }
    private lazy var defaultDeviceHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self, self.running else { return }
        self.detachListeners()
        self.primed = false          // don't fire a HUD just for switching
        self.attachToDefaultDevice()
    }

    func start() {
        guard !running else { return }
        running = true
        attachToDefaultDevice()

        // Re-attach when the user switches output (headphones, AirPlay, …).
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, defaultDeviceHandler)
    }

    func stop() {
        guard running else { return }
        running = false
        detachListeners()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, defaultDeviceHandler)
    }

    // MARK: - Wiring

    private func attachToDefaultDevice() {
        guard let id = currentDefaultOutputDevice() else { return }
        deviceID = id

        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, .main, deviceHandler)
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, .main, deviceHandler)

        report()   // primes the baseline without emitting
    }

    private func detachListeners() {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, .main, deviceHandler)
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, .main, deviceHandler)
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
