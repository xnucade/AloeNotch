import Cocoa
import ApplicationServices

/// Intercepts the hardware volume / brightness keys before macOS handles them.
///
/// This is the only way to stop the system's own on-screen HUD: `OSDUIHelper`
/// is SIP-protected (it can't be unloaded), and killing it just makes it respawn
/// with a visible flicker. So instead we swallow the key event and apply the
/// change ourselves, which means macOS never draws its HUD at all.
///
/// Consuming events requires an event tap, which requires **Accessibility**
/// permission. Without it `start()` returns false and the caller should leave
/// the system HUD alone rather than showing a second one.
final class MediaKeyInterceptor {
    /// Called with a signed step (fraction of full range) on volume keys.
    var onVolumeStep: ((Float) -> Void)?
    var onMuteToggle: (() -> Void)?
    var onBrightnessStep: ((Float) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Hardware key codes carried in NSSystemDefined subtype-8 events.
    private enum HardwareKey: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to show the "grant Accessibility" prompt.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }

        // NX_SYSDEFINED — the event type hardware media keys arrive as.
        let mask = CGEventMask(1 << 14)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,               // .defaultTap = we may consume
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyInterceptor>
                    .fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        runLoopSource = nil
        tap = nil
    }

    // MARK: - Tap callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long; re-arm and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8            // aux control buttons
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let isKeyDown = ((data & 0x0000_FF00) >> 8) == 0x0A

        guard let key = HardwareKey(rawValue: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        // Shift+Option is macOS's quarter-step modifier.
        let fine = nsEvent.modifierFlags.isSuperset(of: [.shift, .option])
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        if isKeyDown {
            switch key {
            case .soundUp:        onVolumeStep?(step)
            case .soundDown:      onVolumeStep?(-step)
            case .mute:           onMuteToggle?()
            case .brightnessUp:   onBrightnessStep?(step)
            case .brightnessDown: onBrightnessStep?(-step)
            }
        }
        // Swallow key-down *and* key-up so macOS never sees the press.
        return nil
    }
}
