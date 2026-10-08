import Foundation
import ObjectiveC

/// Reports keyboard-backlight changes on the built-in keyboard.
///
/// Recent MacBooks have no backlight keys: the level is set from Control
/// Center, and the system shows nothing when it changes. CoreBrightness's
/// private `KeyboardBrightnessClient` both reads the level and pushes a
/// notification when it changes, so this listens rather than polls. If the
/// class or any selector is missing, `isAvailable` stays false and the
/// readout simply never appears.
final class KeyboardBacklightMonitor {
    /// Called on the main queue with the new level (0…1) when it changes.
    var onChange: ((Float) -> Void)?

    private(set) var isAvailable = false

    private typealias Register = @convention(c) (
        AnyObject, Selector, NSArray, UInt64,
        @escaping @convention(block) (AnyObject?, AnyObject?) -> Void
    ) -> Void
    private typealias Unregister = @convention(c) (AnyObject, Selector) -> Void

    private static let registerSelector = NSSelectorFromString("registerNotificationForKeys:keyboardID:block:")
    private static let unregisterSelector = NSSelectorFromString("unregisterKeyboardNotificationBlock")
    private static let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
    /// The user's level, as the Control Center slider sets it — not the
    /// momentary output, which idle dimming and ambient light move.
    private static let brightnessKey = "KeyboardBacklightBrightness"

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private var listening = false
    private var last: Float = -1

    init() {
        load()
    }

    private func load() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              bundle.load(),
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let client = type.init()
        let needed = [Self.registerSelector, Self.unregisterSelector, Self.builtInSelector,
                      NSSelectorFromString("copyKeyboardBacklightIDs")]
        guard needed.allSatisfy({ client.responds(to: $0) }),
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                  .takeRetainedValue() as? [NSNumber] else { return }
        typealias IsBuiltIn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        let isBuiltIn = unsafeBitCast(client.method(for: Self.builtInSelector), to: IsBuiltIn.self)
        guard let id = ids.map(\.uint64Value).first(where: { isBuiltIn(client, Self.builtInSelector, $0) })
        else { return }
        self.client = client
        self.keyboardID = id
        isAvailable = true
    }

    func start() {
        guard isAvailable, !listening, let client else { return }
        listening = true
        let register = unsafeBitCast(client.method(for: Self.registerSelector), to: Register.self)
        register(client, Self.registerSelector, [Self.brightnessKey], keyboardID) { [weak self] key, value in
            guard (key as? String) == Self.brightnessKey,
                  let level = (value as? NSNumber)?.floatValue else { return }
            DispatchQueue.main.async { self?.report(min(1, max(0, level))) }
        }
    }

    func stop() {
        guard listening, let client else { return }
        listening = false
        let unregister = unsafeBitCast(client.method(for: Self.unregisterSelector), to: Unregister.self)
        unregister(client, Self.unregisterSelector)
        last = -1
    }

    private func report(_ level: Float) {
        guard listening, abs(level - last) > 0.005 else { return }
        last = level
        onChange?(level)
    }
}
