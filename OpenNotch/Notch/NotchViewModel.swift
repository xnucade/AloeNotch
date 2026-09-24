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

    /// As an announcement. `.direct` priority because the user is holding a key
    /// right now, and nothing arriving in the background may bury it.
    /// As an announcement. The artwork colour is passed in rather than read
    /// here, because `NotchHUD` is a value type that knows nothing about what
    /// is playing.
    private var spokenName: String {
        switch self {
        case .volume(_, let muted): muted ? "Volume muted" : "Volume"
        case .brightness: "Brightness"
        }
    }

    func activity(artwork: Color? = nil) -> LiveActivity {
        let isVolume = if case .volume = self { true } else { false }
        return LiveActivity(
            kind: "system.hud",
            symbol: icon,
            tint: AppSettings.shared.hudTint(volume: isVolume, artwork: artwork),
            spokenName: spokenName,
            trailing: .level(Double(level)),
            size: .wide,
            duration: 1.5,
            priority: LiveActivity.Priority.direct
        )
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

    /// Everything transient the notch announces. See `LiveActivity`.
    let activities = LiveActivityCenter()
    let clipboard = ClipboardManager()
    let audioOutput = AudioOutputController()
    let caffeine = CaffeineController()
    lazy var timer = TimerModel(center: activities)

    /// Watches for hardware worth announcing. See `ActivityDetectors`.
    private lazy var detectors = ActivityDetectors(center: activities)

    /// Convenience for the many call sites that only care about the panel being
    /// open. Kept so this refactor doesn't churn every view at once.
    var isExpanded: Bool { panelState.isExpanded }

    /// Whether the pointer is inside the active region. An input to the state
    /// machine, not a state itself.
    private var isHovering = false

    /// The pointer is resting on the closed notch and the panel is deciding
    /// whether to open (or, in click mode, waiting for the click). The view
    /// swells the surface slightly while this is true. Only drawn when not
    /// expanded, so it can stay true through the open without resizing
    /// anything — which also means opening changes only `panelState`, and the
    /// open spring is the one animation in charge of that frame.
    @Published private(set) var isAnticipating = false
    private var intentWorkItem: DispatchWorkItem?

    /// Held open by the keyboard shortcut, until it is pressed again.
    @Published private(set) var isPinnedOpen = false


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
            self.pushIfAtLimit(previous: previous, delta: delta)
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
            self.pushIfAtLimit(previous: previous, delta: delta)
        }

        settings.$showHUD
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateHUDPipeline(enabled: enabled)
            }
            .store(in: &cancellables)

        // Plugging in the charger gets a brief acknowledgement in the notch —
        // the Dynamic Island's signature moment, and the one time battery state
        // changes because of something the user physically just did.
        //
        // Driven off `isPluggedIn` rather than `isCharging`: a Mac plugged in at
        // 100% is not charging, but connecting the cable is still the event
        // worth confirming. `dropFirst` so launching with the charger already
        // connected doesn't announce itself.
        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] plugged in
                guard plugged else { return }
                self?.flashChargingPeek()
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

        // Device announcements follow their toggle, so switching them off
        // stops the watching rather than just hiding the result.
        // The shortcut follows its own setting, and re-registers when the
        // combo changes so a collision can be resolved without relaunching.
        settings.$hotKeyEnabled
            .combineLatest(settings.$hotKeyCombo)
            .removeDuplicates { $0 == $1 }
            .sink { enabled, combo in
                if enabled {
                    HotKeyManager.shared.register(combo)
                } else {
                    HotKeyManager.shared.unregister()
                }
            }
            .store(in: &cancellables)

        HotKeyManager.shared.onFire = { [weak self] in self?.toggleFromKeyboard() }

        // Polling only while the module is on. A clipboard watcher that runs
        // when nothing displays it is pure surveillance with no payoff.
        settings.$showClipboard
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                if on { self.clipboard.start() } else { self.clipboard.stop(); self.clipboard.clear() }
            }
            .store(in: &cancellables)

        settings.$showDeviceEvents
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.detectors.start() } else { self.detectors.stop() }
            }
            .store(in: &cancellables)

        // Any announcement appearing or expiring resizes the strip — and so
        // does a resident one starting or ending, which is what a timer does.
        //
        // `receive(on:)` on all three, and it is not optional. `@Published`
        // publishes in `willSet`, so a sink that runs synchronously re-reads
        // the property and gets the value it had *before* the change.
        // `targetState()` re-reads every input, so without the hop the whole
        // state machine runs exactly one step behind: the strip grew its wing
        // as an announcement disappeared and shrank as one arrived, which is
        // why volume and brightness readouts could leave a wide empty strip
        // sitting on screen with nothing drawn in it.
        activities.$current
            .combineLatest(activities.$resident)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)

        // The media peek is an explicit state rather than something the view
        // re-derives, so the two inputs that produce it drive the state machine
        // directly — with the same hop, for the same reason.
        media.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)

        settings.$showMedia
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)
    }

    // MARK: - State machine

    // Hover handling: a short intent delay on the way in (see `OpenTrigger`),
    // and a small close delay on the way out so the panel doesn't flicker
    // when the cursor briefly leaves the content.
    //
    // `immediate` skips the intent delay — a file being dragged to the notch
    // is never an accident.
    func hoverChanged(_ inside: Bool, immediate: Bool = false) {
        collapseWorkItem?.cancel()
        intentWorkItem?.cancel()
        if inside {
            // Coming back inside the close grace period, or already open:
            // nothing to decide.
            let delay = immediate || isHovering || panelState.isExpanded
                ? 0 : settings.openTrigger.intentDelay
            guard let delay else {
                isAnticipating = true   // click mode: swell and wait
                return
            }
            if delay == 0 {
                isHovering = true
                refreshState()
                return
            }
            isAnticipating = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isHovering = true
                self.refreshState()
            }
            intentWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            // Relax the swell now. It is only drawn while closed, so if the
            // panel is open this changes nothing until the close below.
            isAnticipating = false
            guard isHovering || isPinnedOpen else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isHovering = false
                // Hovering a keyboard-opened panel and then leaving hands
                // control back to the pointer. Without this the panel can sit
                // open across the top of the screen indefinitely because the
                // user forgot they opened it with a key, and the obvious
                // gesture for closing it — mousing away — does nothing.
                self.isPinnedOpen = false
                self.refreshState()
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverGrace, execute: work)
        }
    }

    /// A click on the closed notch. Opens it in every mode — in click mode
    /// it is the only way in, and in the hover modes it just skips the wait.
    func notchClicked() {
        guard !panelState.isExpanded else { return }
        intentWorkItem?.cancel()
        isHovering = true
        refreshState()
    }

    // MARK: Gestures

    private var swipeTracker = SwipeTracker()

    /// How far a two-finger pull has stretched the closed strip, already
    /// rubber-banded. The strip follows the fingers until the swipe fires,
    /// so opening it feels like pulling it down rather than triggering it.
    @Published private(set) var pull: CGFloat = 0
    static let pullLimit: CGFloat = 10

    /// Swipe-to-switch in the focused layout. A counter rather than a
    /// value so the same direction twice is still two changes.
    struct ModuleStep: Equatable { var count = 0; var direction = 1 }
    @Published private(set) var moduleStep = ModuleStep()

    /// Two-finger swipes over the notch:
    /// - down on the closed strip opens it (skipping the hover delay),
    /// - up on the open panel closes it,
    /// - left/right on the media peek skips tracks,
    /// - left/right in the focused layout switches module.
    func handleScroll(_ event: NSEvent) -> Bool {
        // Trackpads and Magic Mouse only. A wheel click over the notch is
        // far more likely to be scrolling the window underneath.
        guard event.hasPreciseScrollingDeltas else { return false }
        let phase: SwipeTracker.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else {
            return false
        }
        // Finger space: natural scrolling reports the content's direction,
        // which is the fingers' direction; the classic setting is reversed.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let swipe = swipeTracker.feed(phase, dx: event.scrollingDeltaX * sign,
                                      dy: event.scrollingDeltaY * sign)

        let stretched = panelState.isExpanded ? 0
            : SwipeTracker.rubberBand(swipeTracker.pull, limit: Self.pullLimit)
        if stretched != pull { pull = stretched }

        guard let swipe else { return true }
        let expanded = panelState.isExpanded
        switch swipe {
        case .down where !expanded:
            notchClicked()
        case .up where expanded:
            dismiss()
        case .left where !expanded && panelState.showsMedia:
            media.next()
        case .right where !expanded && panelState.showsMedia:
            media.previous()
        case .left where expanded:
            moduleStep = ModuleStep(count: moduleStep.count + 1, direction: 1)
        case .right where expanded:
            moduleStep = ModuleStep(count: moduleStep.count + 1, direction: -1)
        default:
            return true
        }
        Haptics.tick()
        return true
    }

    /// Close without the pointer leaving: a swipe up, or VoiceOver, which
    /// opens the panel without the pointer ever entering it.
    func dismiss() {
        intentWorkItem?.cancel()
        collapseWorkItem?.cancel()
        isAnticipating = false
        isHovering = false
        isPinnedOpen = false
        refreshState()
    }

    /// Grace period before an un-hover closes the panel, so brushing past the
    /// edge of the content doesn't collapse it.
    private static let hoverGrace: TimeInterval = 0.25

    /// The state the current inputs imply.
    ///
    /// The precedence lives in `PanelStateReducer` rather than here so it can be
    /// tested without standing up a view model and all seven of its managers.
    /// This function's only job is gathering the inputs.
    private func targetState() -> PanelState {
        PanelStateReducer.state(for: .init(
            isHovering: isHovering,
            isPinned: isPinnedOpen,
            activity: activities.showing?.size,
            activityIsResident: activities.showing?.isResident ?? false,
            mediaPlaying: media.isPlaying,
            showMedia: settings.showMedia
        ))
    }

    /// Open or close from the keyboard.
    ///
    /// Pinning rather than faking a hover: a hover ends when the pointer moves,
    /// and there is no pointer here. Pressing the shortcut again is the only
    /// thing that closes it, which is predictable in a way that "closes when
    /// you happen to mouse over and away" is not.
    func toggleFromKeyboard() {
        isPinnedOpen.toggle()
        // Cancel any pending hover-out collapse, or a stale one could shut a
        // panel the user has just deliberately opened.
        collapseWorkItem?.cancel()
        refreshState()
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
        #if DEBUG
        FrameBudget.shared.watch("\(old) → \(new)", on: metrics?.screen, for: settle + 0.1)
        #endif

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
        let aw = a.width + metrics.bubbleExtent(for: old)
        let bw = b.width + metrics.bubbleExtent(for: new)
        return bw < aw || b.height < a.height
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
            activities.dismiss(kind: "system.hud")
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
            activities.dismiss(kind: "system.hud")
            guard trustPoll == nil else { return }
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, MediaKeyInterceptor.isTrusted else { return }
                self.updateHUDPipeline(enabled: self.settings.showHUD)
            }
        }
    }

    /// Briefly widen the strip to acknowledge the charger being connected.
    private func flashChargingPeek() {
        guard settings.showBattery else { return }
        activities.present(LiveActivity(
            kind: "system.power",
            symbol: "bolt.fill",
            tint: .green,
            spokenName: "Charging",
            trailing: .text("\(Int((battery.level * 100).rounded()))%"),
            size: .regular,
            duration: 2.0,
            priority: LiveActivity.Priority.action
        ))
    }

    /// Flash a system readout in the notch, replacing any already showing.
    ///
    /// The artwork accent is handed over here because this is the one place
    /// that can see both the readout and what is playing. It is nil when
    /// nothing is, which is what makes the `artwork` tint mode fall back to
    /// white on its own rather than needing a special case.
    /// A step that could not move the level because it was already at the
    /// stop. The readout stretches against the stop instead of doing nothing,
    /// which is how iOS says "that's all there is".
    private func pushIfAtLimit(previous: Float, delta: Float) {
        if delta > 0, previous >= 0.999 { activities.pushAgainstLimit(1) }
        if delta < 0, previous <= 0.001 { activities.pushAgainstLimit(-1) }
    }

    private func present(_ readout: NotchHUD) {
        activities.present(readout.activity(artwork: media.current.accent))
    }

    func tearDown() {
        detectors.stop()
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
    }
}
