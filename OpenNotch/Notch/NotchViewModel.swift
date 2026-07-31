import SwiftUI
import Combine

/// Shared state for everything drawn inside the notch. Owns the feature
/// managers (media, tray, battery, calendar, weather) and the expand/collapse
/// state.

/// What the notch surface is currently showing.
///
/// This used to be a `Bool` plus a peek condition (`showMedia && isPlaying`)
/// evaluated independently in the view *and* in the window controller's
/// hit-testing — two places deriving the same truth, free to disagree. Making
/// it one value means the drawn size and the clickable size are computed from
/// the same thing, and it gives the collapsed → peek → expanded morph a single
/// property for one spring to drive.
enum PanelState: Equatable {
    /// Bare strip, hugging the hardware notch. The app is invisible here.
    case collapsed
    /// Strip grown into "wings" either side of the notch, showing a glanceable
    /// indicator. The two kinds need different widths, so they are not one case.
    case peek(Peek)
    /// Full panel, dropped down below the notch.
    case expanded

    enum Peek: Equatable {
        /// Now-playing artwork + equalizer.
        case media
        /// Volume / brightness readout, which needs more room than media.
        case hud
    }

    var isExpanded: Bool { self == .expanded }

    /// Short name for diagnostics.
    var debugName: String {
        switch self {
        case .collapsed:     "collapsed"
        case .peek(.media):  "peek(media)"
        case .peek(.hud):    "peek(hud)"
        case .expanded:      "expanded"
        }
    }
}

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
    /// What the surface is showing. Only ever changed through `apply(_:)`, so
    /// every transition is animated by exactly one spring.
    @Published private(set) var panelState: PanelState = .collapsed

    /// The state the *hit-test* region should use.
    ///
    /// It matches `panelState` except while collapsing, where it trails.
    /// `panelState` flips the moment the pointer leaves, but the panel takes
    /// the whole collapse animation to actually shrink — and for that window it
    /// is still on screen, still under the cursor. Shrinking the clickable
    /// region immediately is what makes the panel feel like it closes out from
    /// under you when you move back into it.
    @Published private(set) var hitTestState: PanelState = .collapsed

    /// The curve the *next* `panelState` change should use.
    ///
    /// Published alongside the state rather than wrapped around it with
    /// `withAnimation`. Wrapping a change to an `@Published` property relies on
    /// the animation transaction surviving the hop across `objectWillChange`
    /// into the view's update, which is not something to bet the whole feel of
    /// the app on — if it does not survive, every transition snaps and there is
    /// no visible clue as to why. The view applies this explicitly with
    /// `.animation(_:value:)`, which is unambiguous.
    @Published private(set) var stateAnimation: Animation = Motion.expand

    @Published var metrics: NotchMetrics?
    @Published var hud: NotchHUD?

    /// Convenience for the many call sites that only care about the panel being
    /// open. Kept so this refactor doesn't churn every view at once.
    var isExpanded: Bool { panelState.isExpanded }

    /// Whether the pointer is inside the active region. An input to the state
    /// machine, not a state itself.
    private var isHovering = false

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
    /// whole surface moves as one piece. The curves themselves now live in
    /// `Motion` (Design/Theme.swift) alongside every other animation in the
    /// app; these stay as the names the notch code already uses.
    static var expandAnimation: Animation { Motion.expand }
    static var collapseAnimation: Animation { Motion.collapse }
    /// HUDs and wings share a quicker version of the same curve.
    static var hudAnimation: Animation { Motion.hud }

    private var collapseWorkItem: DispatchWorkItem?
    private var hitTestTrail: DispatchWorkItem?
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
            let previous = self.volume.level()
            let newLevel = min(1, max(0, previous + delta))
            if delta > 0 { self.volume.setMuted(false) }   // raising unmutes, as macOS does
            self.volume.setLevel(newLevel)
            self.present(.volume(level: newLevel, muted: newLevel <= 0))
            // Only when the level actually moved. Holding the key down at 0 or
            // 1 should feel like hitting a stop, not like it is still stepping.
            if newLevel != previous { Haptics.tick() }
        }
        mediaKeys.onMuteToggle = { [weak self] in
            guard let self else { return }
            let nowMuted = !self.volume.muted()
            self.volume.setMuted(nowMuted)
            self.present(.volume(level: self.volume.level(), muted: nowMuted))
        }
        mediaKeys.onBrightnessStep = { [weak self] delta in
            guard let self else { return }
            let previous = self.brightness.level()
            let newLevel = min(1, max(0, previous + delta))
            self.brightness.setLevel(newLevel)
            self.present(.brightness(level: newLevel))
            if newLevel != previous { Haptics.tick() }
        }

        settings.$showHUD
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateHUDPipeline(enabled: enabled)
            }
            .store(in: &cancellables)

        // Permissions granted from Settings or onboarding reach the features
        // that need them without a relaunch.
        PermissionRequester.shared.$calendarStatus
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.calendar.reevaluateAccess() }
            .store(in: &cancellables)

        PermissionRequester.shared.$locationStatus
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.weather.reevaluateAccess() }
            .store(in: &cancellables)

        // The media peek is now an explicit state rather than something the
        // view re-derives, so the two inputs that produce it have to drive the
        // state machine directly.
        media.$isPlaying
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)

        settings.$showMedia
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)
    }

    // MARK: - State machine

    // Hover handling with a small close delay so the panel doesn't flicker
    // when the cursor briefly leaves the content.
    func hoverChanged(_ inside: Bool) {
        collapseWorkItem?.cancel()
        if inside {
            isHovering = true
            refreshState()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.isHovering = false
                self?.refreshState()
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverGrace, execute: work)
        }
    }

    /// Grace period before an un-hover closes the panel, so brushing past the
    /// edge of the content doesn't collapse it.
    private static let hoverGrace: TimeInterval = 0.25

    /// The state the current inputs imply. Pure — it reads, never writes.
    ///
    /// Order matters: hovering always wins (the user is actively asking for the
    /// panel), then a HUD, which is transient and time-critical, then media.
    private func targetState() -> PanelState {
        if isHovering { return .expanded }
        if hud != nil { return .peek(.hud) }
        if settings.showMedia && media.isPlaying { return .peek(.media) }
        return .collapsed
    }

    /// Recompute and animate to whatever the inputs now imply.
    private func refreshState() {
        apply(targetState())
    }

    private func apply(_ new: PanelState) {
        let old = panelState
        guard new != old else { return }

        // Opening gets the bouncier spring; closing gets the settled one; the
        // small width changes between peeks get the quick one.
        let animation: Animation
        let settle: TimeInterval
        switch (old, new) {
        case (_, .expanded): animation = Self.expandAnimation; settle = Self.expandSettle
        case (.expanded, _): animation = Self.collapseAnimation; settle = Self.collapseSettle
        default:             animation = Self.hudAnimation; settle = Self.hudSettle
        }

        // Order matters: the view reads `stateAnimation` when `panelState`
        // changes, so the curve has to be in place first.
        //
        // Reduce Motion is resolved here rather than in the view because this
        // is the single place the panel's curve is chosen — doing it at the
        // call site would mean every future transition has to remember to.
        stateAnimation = Motion.resolve(
            animation,
            reduceMotion: AccessibilityPreferences.shared.reduceMotion
        )
        panelState = new

        // The invariant: the clickable region is never smaller than what is
        // actually drawn. Growing is safe to apply at once — a region larger
        // than the pixels only makes the panel easier to reach. Shrinking has
        // to wait for the animation, or the surface stops taking the mouse
        // while it is still visibly there.
        hitTestTrail?.cancel()
        guard isShrinking(from: old, to: new) else {
            hitTestState = new
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hitTestState = self.panelState
        }
        hitTestTrail = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
    }

    /// Whether the surface is getting smaller in either axis. Falls back to the
    /// expanded/not comparison before metrics have been measured.
    private func isShrinking(from old: PanelState, to new: PanelState) -> Bool {
        guard let metrics else { return old.isExpanded && !new.isExpanded }
        let a = metrics.size(for: old), b = metrics.size(for: new)
        return b.width < a.width || b.height < a.height
    }

    // How long to hold the outgoing hit region, per transition. Each sits just
    // past its animation's duration so the region never shrinks while pixels
    // are still moving.
    private static let expandSettle: TimeInterval = 0.42
    private static let collapseSettle: TimeInterval = 0.34
    private static let hudSettle: TimeInterval = 0.30

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
            refreshState()
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
            refreshState()
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
        // The HUD is an input to the state machine — raising one widens the
        // strip into HUD wings unless the panel is already open.
        refreshState()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(Self.hudAnimation) { self.hud = nil }
            self.refreshState()
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
        collapseWorkItem?.cancel()
        hitTestTrail?.cancel()
        hudDismiss?.cancel()
    }
}
