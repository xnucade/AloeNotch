import SwiftUI
import Combine

/// Shared state for everything drawn inside the notch. Owns the feature
/// managers (media, tray, battery, calendar, weather) and the expand/collapse
/// state.
/// A transient system readout shown in the notch (replacing macOS's own HUD).
enum NotchHUD: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)

    var level: Float {
        switch self {
        case .volume(let level, let muted): return muted ? 0 : level
        case .brightness(let level): return level
        }
    }

    var icon: String {
        switch self {
        case .volume(let level, let muted):
            if muted || level <= 0 { return "speaker.slash.fill" }
            return level < 0.34 ? "speaker.wave.1.fill"
                 : level < 0.67 ? "speaker.wave.2.fill"
                 : "speaker.wave.3.fill"
        case .brightness(let level):
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}

final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var metrics: NotchMetrics?
    @Published var hud: NotchHUD?

    /// Opens the preferences window; set by AppDelegate.
    var onOpenSettings: (() -> Void)?

    let media = NowPlayingManager()
    let tray = TrayModel()
    let battery = BatteryMonitor()
    let calendar = CalendarModel()
    let weather = WeatherProvider()
    let volume = VolumeMonitor()
    let brightness = BrightnessMonitor()
    let mediaKeys = MediaKeyInterceptor()
    let settings = AppSettings.shared

    /// Whether we hold Accessibility permission. Without it we can't swallow the
    /// volume/brightness keys, so we leave macOS's own HUD alone rather than
    /// stacking a second one on top of it.
    @Published private(set) var canReplaceSystemHUD = MediaKeyInterceptor.isTrusted

    /// Springs shared by everything that animates with the expansion so the
    /// whole surface moves as one piece. `.smooth` is SwiftUI's fluid curve —
    /// a touch of bounce opening, none closing, so it settles cleanly instead
    /// of jittering at the end.
    static let expandAnimation: Animation = .smooth(duration: 0.40, extraBounce: 0.10)
    static let collapseAnimation: Animation = .smooth(duration: 0.32)
    /// HUDs and wings share a quicker version of the same curve.
    static let hudAnimation: Animation = .smooth(duration: 0.28)

    private var collapseWorkItem: DispatchWorkItem?
    private var hudDismiss: DispatchWorkItem?
    private var trustPoll: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        media.start()
        battery.start()

        // Calendar and weather follow their toggles so a disabled feature does
        // no permission prompting or polling at all. They're also gated on the
        // welcome having been seen, so a first-time user isn't hit with system
        // permission prompts before they know what the app is.
        settings.$showCalendar
            .combineLatest(settings.$hasSeenWelcome)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.calendar.start() } else { self?.calendar.stop() }
            }
            .store(in: &cancellables)

        settings.$showWeather
            .combineLatest(settings.$hasSeenWelcome)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.weather.start() } else { self?.weather.stop() }
            }
            .store(in: &cancellables)

        // Volume / brightness HUD. Observers catch changes from any source
        // (other apps, Control Center) and raise the readout.
        volume.onChange = { [weak self] level, muted in
            self?.present(.volume(level: level, muted: muted))
        }
        brightness.onChange = { [weak self] level in
            self?.present(.brightness(level: level))
        }

        // Intercepted keys: apply the change ourselves and show the readout
        // immediately, rather than waiting on the observer.
        mediaKeys.onVolumeStep = { [weak self] delta in
            guard let self else { return }
            let newLevel = min(1, max(0, self.volume.level() + delta))
            if delta > 0 { self.volume.setMuted(false) }   // raising unmutes, as macOS does
            self.volume.setLevel(newLevel)
            self.present(.volume(level: newLevel, muted: newLevel <= 0))
        }
        mediaKeys.onMuteToggle = { [weak self] in
            guard let self else { return }
            let nowMuted = !self.volume.muted()
            self.volume.setMuted(nowMuted)
            self.present(.volume(level: self.volume.level(), muted: nowMuted))
        }
        mediaKeys.onBrightnessStep = { [weak self] delta in
            guard let self else { return }
            let newLevel = min(1, max(0, self.brightness.level() + delta))
            self.brightness.setLevel(newLevel)
            self.present(.brightness(level: newLevel))
        }

        settings.$showHUD
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateHUDPipeline(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    // Hover handling with a small close delay so the panel doesn't flicker
    // when the cursor briefly leaves the content.
    func hoverChanged(_ inside: Bool) {
        collapseWorkItem?.cancel()
        if inside {
            withAnimation(Self.expandAnimation) {
                isExpanded = true
            }
        } else {
            let work = DispatchWorkItem { [weak self] in
                withAnimation(Self.collapseAnimation) {
                    self?.isExpanded = false
                }
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    /// Start or stop the HUD stack. We only show our own readout once we can
    /// actually suppress the system one — otherwise the user gets two HUDs,
    /// which is worse than leaving macOS to it.
    private func updateHUDPipeline(enabled: Bool) {
        canReplaceSystemHUD = MediaKeyInterceptor.isTrusted

        guard enabled else {
            mediaKeys.stop()
            volume.stop()
            brightness.stop()
            trustPoll?.invalidate(); trustPoll = nil
            hud = nil
            return
        }

        if mediaKeys.start() {
            canReplaceSystemHUD = true
            volume.start()
            brightness.start()
            trustPoll?.invalidate(); trustPoll = nil
        } else {
            // Not trusted yet — stay out of the way and watch for the grant.
            canReplaceSystemHUD = false
            volume.stop()
            brightness.stop()
            hud = nil
            guard trustPoll == nil else { return }
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, MediaKeyInterceptor.isTrusted else { return }
                self.updateHUDPipeline(enabled: self.settings.showHUD)
            }
        }
    }

    /// Flash a system readout in the notch, replacing any HUD already showing.
    private func present(_ readout: NotchHUD) {
        hudDismiss?.cancel()
        withAnimation(Self.hudAnimation) { hud = readout }

        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.hudAnimation) { self?.hud = nil }
        }
        hudDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func tearDown() {
        media.stop()
        battery.stop()
        calendar.stop()
        weather.stop()
        volume.stop()
        brightness.stop()
        mediaKeys.stop()
        trustPoll?.invalidate()
        trustPoll = nil
    }
}
