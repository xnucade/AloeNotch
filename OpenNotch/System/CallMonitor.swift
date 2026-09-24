import Foundation
import CoreAudio

/// Whether the Mac is probably in a call, judged by whether anything is
/// recording from the default input device.
///
/// This is the signal behind blurring the clipboard. Knowing directly that the
/// screen is being shared would need Screen Recording permission for a
/// feature whose whole point is privacy, and `sharingType = .none` alone isn't
/// honoured by every capturer. A live microphone is the cheap proxy: nearly
/// every screen share happens inside a call. No permission is needed to ask
/// whether *some* process is using the device.
final class CallMonitor: ObservableObject {
    static let shared = CallMonitor()

    @Published private(set) var micInUse = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private lazy var runningHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }

    private init() {
        attach()
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main
        ) { [weak self] _, _ in
            self?.detach()
            self?.attach()
        }
    }

    private func attach() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &defaultDeviceAddress, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else {
            micInUse = false
            return
        }
        deviceID = id
        AudioObjectAddPropertyListenerBlock(deviceID, &runningAddress, .main, runningHandler)
        refresh()
    }

    private func detach() {
        guard deviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &runningAddress, .main, runningHandler)
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func refresh() {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let ok = deviceID != kAudioObjectUnknown
            && AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &size, &running) == noErr
        let now = ok && running != 0
        if now != micInUse { micInUse = now }
    }
}
