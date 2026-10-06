import Foundation
import CoreAudio

/// The default input's mute switch, from CoreAudio property listeners.
///
/// Needs no permission and never opens the microphone: mute is a property
/// of the device, readable without recording anything, so the orange
/// indicator never appears on its account. An input with no mute control
/// (many don't have one) is simply not watched.
final class MicrophoneMuteMonitor {
    /// Called with the new state when the mute switch flips. Not called for
    /// switching to a different input, which is not a mute.
    var onChange: ((Bool) -> Void)?

    private var running = false
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var lastMuted: Bool?

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // Kept, because CoreAudio removes a listener only by the block it was
    // added with.
    private lazy var muteHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.report()
    }
    private lazy var inputHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self, self.running else { return }
        self.detach()
        self.attach()
    }

    func start() {
        guard !running else { return }
        running = true
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, .main, inputHandler)
        attach()
    }

    func stop() {
        guard running else { return }
        running = false
        detach()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, .main, inputHandler)
    }

    private func attach() {
        guard let id = defaultInput(), AudioObjectHasProperty(id, &muteAddress) else { return }
        deviceID = id
        AudioObjectAddPropertyListenerBlock(id, &muteAddress, .main, muteHandler)
        lastMuted = isMuted()   // the baseline, not an event
    }

    private func detach() {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, .main, muteHandler)
        deviceID = AudioObjectID(kAudioObjectUnknown)
        lastMuted = nil
    }

    private func report() {
        guard let muted = isMuted(), let before = lastMuted, muted != before else { return }
        lastMuted = muted
        onChange?(muted)
    }

    private func defaultInput() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, 0, nil, &size, &id)
        return status == noErr && id != AudioObjectID(kAudioObjectUnknown) ? id : nil
    }

    private func isMuted() -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }
}
