import Foundation
import AppKit
import CoreAudio

/// Watches for things worth announcing, and hands them to `LiveActivityCenter`.
///
/// Every detector here is deliberately **permission-free**. Watching ~/Desktop
/// for new screenshots or ~/Downloads for finished downloads would make better
/// announcements, but both directories are TCC-protected, so the first thing a
/// new user would meet is a "AloeNotch wants to access files" prompt. A feature
/// that opens with a permission dialog is a feature most people decline, and
/// the notch would then be quiet for exactly the users who said no.
///
/// Audio output and mounted volumes need nothing, are noticed constantly, and
/// are the two moments where "what just happened?" is a real question.
final class ActivityDetectors {
    private let center: LiveActivityCenter
    private let audio = AudioOutputDetector()
    private var volumeObservers: [NSObjectProtocol] = []

    init(center: LiveActivityCenter) {
        self.center = center
    }

    func start() {
        startAudioOutput()
        startVolumes()
    }

    func stop() {
        audio.stop()
        volumeObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        volumeObservers.removeAll()
    }

    // MARK: Audio output

    /// The AirPods moment. Connecting headphones changes the *default output
    /// device*, which CoreAudio will tell us about without asking the user for
    /// anything — unlike Bluetooth APIs, which prompt.
    private func startAudioOutput() {
        audio.onChange = { [weak self] name in
            self?.center.present(LiveActivity(
                kind: "system.audioOutput",
                symbol: Self.symbol(forOutput: name),
                tint: .white,
                title: name,
                trailing: .none,
                size: .wide,
                duration: 2.2,
                priority: LiveActivity.Priority.ambient
            ))
        }
        audio.start()
    }

    /// Best-effort glyph for a device name. Falls back to a speaker rather than
    /// guessing wrongly — a made-up icon reads worse than a generic one.
    static func symbol(forOutput name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max")            { return "airpods.max" }
        if n.contains("airpods pro")            { return "airpods.pro" }
        if n.contains("airpods")                { return "airpods" }
        if n.contains("beats") || n.contains("headphone") { return "headphones" }
        if n.contains("display") || n.contains("studio") || n.contains("monitor") {
            return "display"
        }
        if n.contains("macbook") || n.contains("built-in") || n.contains("internal") {
            return "laptopcomputer"
        }
        if n.contains("homepod")                { return "homepod.fill" }
        if n.contains("tv")                     { return "appletv.fill" }
        return "hifispeaker.fill"
    }

    // MARK: Volumes

    /// A drive appearing or leaving. `didMount` fires for disk images and
    /// network shares too, which is correct — "something is now mounted" is the
    /// same news whatever produced it.
    private func startVolumes() {
        let nc = NSWorkspace.shared.notificationCenter

        volumeObservers.append(nc.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let name = Self.volumeName(from: note) else { return }
            self?.center.present(LiveActivity(
                kind: "system.volume",
                symbol: "externaldrive.fill.badge.plus",
                tint: .white,
                title: name,
                trailing: .none,
                size: .wide,
                duration: 2.2,
                priority: LiveActivity.Priority.ambient
            ))
        })

        // Unmount is announced because ejecting is the one case where people
        // genuinely wait for confirmation before pulling the cable.
        volumeObservers.append(nc.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let name = Self.volumeName(from: note) else { return }
            self?.center.present(LiveActivity(
                kind: "system.volume",
                symbol: "externaldrive.badge.checkmark",
                tint: .green,
                title: name,
                trailing: .none,
                size: .wide,
                duration: 2.2,
                priority: LiveActivity.Priority.action
            ))
        })
    }

    private static func volumeName(from note: Notification) -> String? {
        if let name = note.userInfo?["NSWorkspaceVolumeLocalizedNameKey"] as? String {
            return name
        }
        if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
            return url.lastPathComponent
        }
        return nil
    }
}

// MARK: - CoreAudio default-output listener

/// Reports the system's default output device whenever it changes.
private final class AudioOutputDetector {
    var onChange: ((String) -> Void)?

    private var listening = false
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !listening else { return }

        // Remember what we start on, so the first callback after launch does
        // not announce the device that was already selected.
        var last = Self.currentOutputName()

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            guard let name = Self.currentOutputName(), name != last else { return }
            last = name
            DispatchQueue.main.async { self.onChange?(name) }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            DispatchQueue.global(qos: .utility), block
        )
        listening = true
    }

    func stop() {
        guard listening, let listener else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            DispatchQueue.global(qos: .utility), listener
        )
        self.listener = nil
        listening = false
    }

    static func currentOutputName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &deviceAddress, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown
        else { return nil }

        return AudioOutputController.name(of: deviceID)
    }
}
