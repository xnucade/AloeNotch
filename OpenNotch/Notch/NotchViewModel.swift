import SwiftUI
import Combine

/// Shared state for everything drawn inside the notch. Owns the feature
/// managers (media, tray, battery, calendar, weather) and the expand/collapse
/// state.
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var metrics: NotchMetrics?

    /// Opens the preferences window; set by AppDelegate.
    var onOpenSettings: (() -> Void)?

    let media = NowPlayingManager()
    let tray = TrayModel()
    let battery = BatteryMonitor()
    let calendar = CalendarModel()
    let weather = WeatherProvider()
    let settings = AppSettings.shared

    /// Springs shared by everything that animates with the expansion so the
    /// whole surface moves as one piece.
    static let expandAnimation: Animation = .snappy(duration: 0.4, extraBounce: 0.12)
    static let collapseAnimation: Animation = .smooth(duration: 0.3)

    private var collapseWorkItem: DispatchWorkItem?
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

    func tearDown() {
        media.stop()
        battery.stop()
        calendar.stop()
        weather.stop()
    }
}
