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
    /// Volume / brightness readouts in the notch instead of the macOS HUD.
    @Published var showHUD: Bool { didSet { save(showHUD, "showHUD") } }
    /// Charge level in the expanded header, and the low/charging hints on the
    /// collapsed strip.
    @Published var showBattery: Bool { didSet { save(showBattery, "showBattery") } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }

    // MARK: Appearance

    /// Chrome tint — calendar highlight, tab selection, control tints. Stored
    /// as `#RRGGBB` because `Color` is not directly persistable and a hex
    /// string stays readable if anyone inspects the defaults by hand.
    ///
    /// Deliberately *not* applied to the ambient glow, which follows the
    /// artwork: that reactivity is the app's signature and a fixed tint would
    /// flatten it.
    @Published var accentHex: String { didSet { save(accentHex, "accentHex") } }

    /// Resolved accent, falling back to the default if the stored value is
    /// somehow unparseable.
    var accent: Color { Color(hex: accentHex) ?? Color(hex: AccentPalette.default)! }

    /// How frosted the glass surfaces are.
    @Published var glassIntensity: GlassIntensity {
        didSet { save(glassIntensity.rawValue, "glassIntensity") }
    }

    /// Appearance of the app's own windows. The notch panel stays black.
    @Published var windowTheme: WindowTheme {
        didSet { save(windowTheme.rawValue, "windowTheme") }
    }

    /// Multiplier on every animation duration: >1 faster, <1 slower.
    @Published var animationSpeed: Double {
        didSet { defaults.set(animationSpeed, forKey: "animationSpeed") }
    }

    /// Width of the expanded panel, in points. Clamped when read so a bad
    /// stored value can't produce a panel wider than the screen.
    @Published var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: "panelWidth") } }

    static let panelWidthRange: ClosedRange<Double> = 520...900

    /// Liquid Glass on the welcome, menu bar panel and settings window.
    /// Offered at first run because it is a taste call, not a capability one:
    /// the material is translucent by design, and over a busy desktop some
    /// people find it harder to read than a solid panel.
    @Published var useGlass: Bool { didSet { save(useGlass, "useGlass") } }

    /// Horizontal nudge of the panel from screen-center, in points (−400…400).
    /// 0 keeps the collapsed strip aligned with the hardware notch.
    @Published var positionOffset: Double { didSet { defaults.set(positionOffset, forKey: "positionOffset") } }

    /// Whether the one-time welcome has been shown. Calendar/weather hold off
    /// on requesting permission until this is true, so the prompts arrive in
    /// context rather than before the user knows what the app is.
    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "ambientGlow": true,
            "showMedia": true,
            "showShelf": true,
            "showCalendar": true,
            "showWeather": true,
            "showHUD": true,
            "showBattery": true,
            "useGlass": true,
            "accentHex": AccentPalette.default,
            "glassIntensity": GlassIntensity.medium.rawValue,
            "windowTheme": WindowTheme.system.rawValue,
            "animationSpeed": 1.0,
            "panelWidth": 616.0,
        ])
        ambientGlow = defaults.bool(forKey: "ambientGlow")
        showMedia = defaults.bool(forKey: "showMedia")
        showShelf = defaults.bool(forKey: "showShelf")
        showCalendar = defaults.bool(forKey: "showCalendar")
        showWeather = defaults.bool(forKey: "showWeather")
        showHUD = defaults.bool(forKey: "showHUD")
        showBattery = defaults.bool(forKey: "showBattery")
        useGlass = defaults.bool(forKey: "useGlass")

        accentHex = defaults.string(forKey: "accentHex") ?? AccentPalette.default
        glassIntensity = GlassIntensity(
            rawValue: defaults.string(forKey: "glassIntensity") ?? ""
        ) ?? .medium
        windowTheme = WindowTheme(
            rawValue: defaults.string(forKey: "windowTheme") ?? ""
        ) ?? .system
        animationSpeed = defaults.double(forKey: "animationSpeed")
        panelWidth = min(max(defaults.double(forKey: "panelWidth"),
                             Self.panelWidthRange.lowerBound),
                         Self.panelWidthRange.upperBound)
        positionOffset = defaults.double(forKey: "positionOffset")   // default 0
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")     // default false
        // Login-item state lives with the system, not in defaults.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: String, _ key: String) {
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
