import SwiftUI
import Combine
import ServiceManagement

/// User-facing preferences, persisted to UserDefaults and observed by both the
/// menu bar panel and the notch UI. Singleton so they share one source of truth.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Album-art-colored glow bleeding out around the panel frame.
    @Published var ambientGlow: Bool { didSet { save(ambientGlow, "ambientGlow") } }
    @Published var showMedia: Bool { didSet { save(showMedia, "showMedia") } }
    @Published var showShelf: Bool { didSet { save(showShelf, "showShelf") } }
    @Published var showCalendar: Bool { didSet { save(showCalendar, "showCalendar") } }
    @Published var showWeather: Bool { didSet { save(showWeather, "showWeather") } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }

    /// Horizontal nudge of the panel from screen-center, in points (−400…400).
    /// 0 keeps the collapsed strip aligned with the hardware notch.
    @Published var positionOffset: Double { didSet { defaults.set(positionOffset, forKey: "positionOffset") } }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "ambientGlow": true,
            "showMedia": true,
            "showShelf": true,
            "showCalendar": true,
            "showWeather": true,
        ])
        ambientGlow = defaults.bool(forKey: "ambientGlow")
        showMedia = defaults.bool(forKey: "showMedia")
        showShelf = defaults.bool(forKey: "showShelf")
        showCalendar = defaults.bool(forKey: "showCalendar")
        showWeather = defaults.bool(forKey: "showWeather")
        positionOffset = defaults.double(forKey: "positionOffset")   // default 0
        // Login-item state lives with the system, not in defaults.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("AloeNotch: launch-at-login change failed: \(error)")
        }
    }
}
