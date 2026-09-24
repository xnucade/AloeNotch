import Foundation
import CoreGraphics

/// Reports display-brightness changes.
///
/// macOS has no public API for reading brightness on Apple Silicon and no change
/// notification at all, so this dynamically loads the private DisplayServices
/// symbol (falling back to CoreDisplay) and polls. If neither symbol resolves,
/// `isAvailable` stays false and the brightness HUD simply never appears.
///
/// The poll is adaptive. The brightness *keys* never need it — the event tap
/// sees them and presents the HUD directly — so polling only exists for
/// changes made elsewhere (the Control Center slider, a script). Idle, it
/// reads once a second; the first change it sees switches it to a fast burst
/// so a slider drag still animates smoothly, then it drops back. It used to
/// read five times a second forever, which was nearly every idle wakeup the
/// app had.
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
    private var burstUntil: Date = .distantPast
    private var last: Float = -1

    private static let idleInterval: TimeInterval = 1.0
    private static let burstInterval: TimeInterval = 0.1
    /// How long the fast poll outlives the last change it saw.
    private static let burstLength: TimeInterval = 2.0
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
        schedule(Self.idleInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        primed = false
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Idle reads can drift; letting the system coalesce them with other
        // wakeups is most of the energy saving. The burst stays precise.
        timer.tolerance = interval == Self.idleInterval ? 0.3 : 0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard let value = read() else { return }
        guard primed else { last = value; primed = true; return }
        // Ignore float jitter; only real user changes should raise the HUD.
        let now = Date()
        if abs(value - last) > 0.005 {
            last = value
            onChange?(value)
            let wasIdle = now >= burstUntil
            burstUntil = now.addingTimeInterval(Self.burstLength)
            if wasIdle { schedule(Self.burstInterval) }
        } else if now >= burstUntil, timer?.timeInterval != Self.idleInterval {
            schedule(Self.idleInterval)
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
