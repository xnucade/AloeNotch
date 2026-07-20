import Foundation
import CoreGraphics

/// Reports display-brightness changes.
///
/// macOS has no public API for reading brightness on Apple Silicon and no change
/// notification at all, so this dynamically loads the private DisplayServices
/// symbol (falling back to CoreDisplay) and polls. The poll is a cheap C call
/// five times a second; if neither symbol resolves, `isAvailable` stays false
/// and the brightness HUD simply never appears.
final class BrightnessMonitor {
    /// Called on the main queue with the new level (0…1) when it changes.
    var onChange: ((Float) -> Void)?

    private(set) var isAvailable = false

    private typealias DisplayServicesGet =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSet =
        @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CoreDisplayGet =
        @convention(c) (CGDirectDisplayID) -> Double
    private typealias CoreDisplaySet =
        @convention(c) (CGDirectDisplayID, Double) -> Void

    private var displayServicesGet: DisplayServicesGet?
    private var displayServicesSet: DisplayServicesSet?
    private var coreDisplayGet: CoreDisplayGet?
    private var coreDisplaySet: CoreDisplaySet?

    /// Whether brightness can be changed (needed to intercept the keys).
    var canSet: Bool { displayServicesSet != nil || coreDisplaySet != nil }

    private var timer: Timer?
    private var last: Float = -1
    private var primed = false

    init() {
        load()
    }

    private func load() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW
        ), let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            displayServicesGet = unsafeBitCast(symbol, to: DisplayServicesGet.self)
            if let setter = dlsym(handle, "DisplayServicesSetBrightness") {
                displayServicesSet = unsafeBitCast(setter, to: DisplayServicesSet.self)
            }
            isAvailable = true
            return
        }
        if let handle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW
        ), let symbol = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") {
            coreDisplayGet = unsafeBitCast(symbol, to: CoreDisplayGet.self)
            if let setter = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") {
                coreDisplaySet = unsafeBitCast(setter, to: CoreDisplaySet.self)
            }
            isAvailable = true
        }
    }

    /// Current level, or 0 if unreadable.
    func level() -> Float { read() ?? 0 }

    /// Set brightness (used when we intercept the brightness keys ourselves).
    func setLevel(_ newValue: Float) {
        let clamped = min(1, max(0, newValue))
        let display = CGMainDisplayID()
        if let displayServicesSet {
            _ = displayServicesSet(display, clamped)
        } else if let coreDisplaySet {
            coreDisplaySet(display, Double(clamped))
        }
        last = clamped   // we already know the new value; don't re-fire from the poll
    }

    func start() {
        guard isAvailable, timer == nil else { return }
        last = read() ?? -1
        primed = true          // swallow the baseline so launch doesn't flash a HUD
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        primed = false
    }

    private func poll() {
        guard let value = read() else { return }
        guard primed else { last = value; primed = true; return }
        // Ignore float jitter; only real user changes should raise the HUD.
        if abs(value - last) > 0.005 {
            last = value
            onChange?(value)
        }
    }

    private func read() -> Float? {
        let display = CGMainDisplayID()
        if let displayServicesGet {
            var value: Float = 0
            return displayServicesGet(display, &value) == 0 ? min(1, max(0, value)) : nil
        }
        if let coreDisplayGet {
            return min(1, max(0, Float(coreDisplayGet(display))))
        }
        return nil
    }
}
