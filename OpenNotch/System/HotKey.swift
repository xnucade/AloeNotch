import AppKit
import Combine
import Carbon.HIToolbox

/// A global keyboard shortcut that opens and closes the notch.
///
/// Until this existed, hovering was the *only* way to open the panel. That is a
/// real accessibility gap rather than a missing convenience: anyone who cannot
/// reliably drive a pointer into a 200pt strip at the very top of the screen
/// simply could not use the app.
///
/// Carbon's `RegisterEventHotKey` rather than `NSEvent.addGlobalMonitorForEvents`,
/// because the monitor route requires Accessibility permission. Accessibility is
/// already requested for the volume-key interception, but that is optional — a
/// user who declines it would otherwise lose keyboard access too, which is
/// exactly the wrong pairing.
enum HotKeyCombo: String, CaseIterable, Identifiable {
    case controlOptionN, optionSpace, controlSpace, controlOptionSpace
    var id: String { rawValue }

    /// Shown in Settings. Real modifier glyphs, in Apple's canonical order.
    var title: String {
        switch self {
        case .controlOptionN:     "⌃⌥N"
        case .optionSpace:        "⌥Space"
        case .controlSpace:       "⌃Space"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    /// A note where a combo is commonly taken, so a shortcut that silently
    /// fails to register is at least explicable.
    var caution: String? {
        switch self {
        case .optionSpace:  "Often taken by Spotlight alternatives."
        case .controlSpace: "macOS uses this for input sources."
        default:            nil
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionN: UInt32(kVK_ANSI_N)
        default:              UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlOptionN:     UInt32(controlKey | optionKey)
        case .optionSpace:        UInt32(optionKey)
        case .controlSpace:       UInt32(controlKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        }
    }
}

final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    /// Fired on the main thread when the combo is pressed.
    var onFire: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x414C4F45)   // 'ALOE'

    private init() {}

    /// Whether the last `register` actually took. Carbon refuses a combo another
    /// process already owns, and reports it here rather than failing silently —
    /// a shortcut that does nothing with no explanation is worse than none.
    @Published private(set) var isRegistered = false

    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            isRegistered = false
            NSLog("AloeNotch: could not register \(combo.title) — another app likely owns it (status \(status)).")
            return false
        }
        hotKey = ref
        isRegistered = true
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isRegistered = false
    }

    /// Installed once and left in place. The callback is a C function pointer,
    /// so it cannot capture — it reaches back through the singleton instead of
    /// juggling an `Unmanaged` pointer through `userData` for one listener.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == HotKeyManager.signature else { return noErr }
            DispatchQueue.main.async { HotKeyManager.shared.onFire?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
