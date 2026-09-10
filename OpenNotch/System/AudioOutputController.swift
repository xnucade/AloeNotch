import Foundation
import CoreAudio
import Combine

/// Lists the Mac's audio output devices and switches between them.
///
/// The other half of the AirPods announcement in `ActivityDetectors`: the notch
/// already tells you when the output changed, and this is where you change it.
/// Switching output is a three-click trip through Control Center or a modifier
/// click most people don't know about, which makes it a good fit for a panel
/// that is already open under the cursor.
///
/// CoreAudio needs no permission for any of this — enumerating devices and
/// setting the default output are both unprivileged.
final class AudioOutputController: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        var symbol: String { ActivityDetectors.symbol(forOutput: name) }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var currentID: AudioObjectID?

    var current: Device? { devices.first { $0.id == currentID } }

    private var listener: AudioObjectPropertyListenerBlock?
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var listAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        refresh()
        observe()
    }

    deinit {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, listener)
        }
        if let deviceListListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &listAddress, .main, deviceListListener)
        }
    }

    /// Make `device` the system output. Anything already playing follows.
    func select(_ device: Device) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, size, &id)
        if status == noErr {
            currentID = device.id
            Haptics.caught()
        } else {
            NSLog("AloeNotch: could not switch output to \(device.name) (status \(status)).")
        }
    }

    // MARK: Enumeration

    private func observe() {
        // Both the current device and the *set* of devices change underneath
        // us — plugging in headphones does the first, waking a Bluetooth
        // speaker does the second — and a stale list is worse than none.
        let onDefault: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()
        }
        listener = onDefault
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, onDefault)

        let onList: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()
        }
        deviceListListener = onList
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, .main, onList)
    }

    func refresh() {
        devices = Self.outputDevices()
        currentID = Self.defaultOutputID()
    }

    private static func defaultOutputID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            // Every device on the system is listed, inputs included. A device
            // is an output only if it has output streams — checking the name
            // for "microphone" would be a guess, and wrong for aggregates.
            guard hasOutputStreams(id), let name = name(of: id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    /// The human-readable name of an audio device.
    ///
    /// Through `Unmanaged`, not a bare `CFString` variable. CoreAudio writes a
    /// retained pointer into the buffer it is handed; giving it a `CFString`
    /// directly means ARC also thinks it owns that variable, so the returned
    /// object is over-released and whatever was there before is leaked. It
    /// happens to work often enough to look correct, which is what makes it
    /// worth spelling out.
    static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        let s = value as String
        return s.isEmpty ? nil : s
    }
}
