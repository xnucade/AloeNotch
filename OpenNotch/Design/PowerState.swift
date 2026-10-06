import Foundation

/// Low Power Mode, observed live.
///
/// Ambient motion is what goes: the glass rim's drift and the dancing
/// equalizer. Both are loops that redraw every frame for as long as music
/// plays, and a slower loop costs almost as much as a fast one — Core
/// Animation still commits a frame every refresh — so they hold still rather
/// than slow down. The live equalizer's audio tap is released too.
final class PowerState: ObservableObject {
    static let shared = PowerState()

    @Published private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
