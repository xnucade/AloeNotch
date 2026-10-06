import AppKit

/// Caps Lock turning on or off.
///
/// A passive event monitor rather than a flag on the media-key tap. That tap
/// is active, so the system waits on it for every event it receives; adding
/// modifier keys to it would make every ⌘ press on the Mac wait on this
/// app's main thread. A monitor is told after the fact and holds nothing up.
///
/// Watching keys from other apps needs Accessibility, so this runs only
/// alongside the volume and brightness readouts, which already have it.
final class CapsLockMonitor {
    var onChange: ((Bool) -> Void)?

    private var monitors: [Any] = []
    private var isOn = false

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        isOn = NSEvent.modifierFlags.contains(.capsLock)
        // Global for other apps, local for this one's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in
            self?.handle($0)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in
            self?.handle($0)
            return $0
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        let on = event.modifierFlags.contains(.capsLock)
        guard on != isOn else { return }
        isOn = on
        onChange?(on)
    }
}
