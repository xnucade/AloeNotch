import AppKit
import Combine

/// Counts down to the next event on the collapsed strip for the ten minutes
/// before it starts. `NextEventWindow` decides when; this owns the clock.
///
/// No polling. One work item waits for the next moment the answer changes —
/// the window opening, or the event starting — and the calendar's own change
/// notifications and a wake from sleep re-decide in between. Dispatch timers
/// don't advance while the Mac sleeps, so the wake is what keeps a countdown
/// from surviving a lid close by ten minutes.
final class NextEventCountdown {
    private static let kind = "calendar.next"

    private weak var center: LiveActivityCenter?
    private var events: [UpcomingEvent] = []
    private var enabled = false
    private var recheck: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(center: LiveActivityCenter, calendar: CalendarModel, settings: AppSettings) {
        self.center = center
        calendar.$upcoming
            .combineLatest(settings.$showNextEventCountdown)
            .sink { [weak self] events, enabled in
                self?.events = events
                self?.enabled = enabled
                self?.evaluate()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
    }

    private func evaluate() {
        recheck?.cancel()
        recheck = nil
        guard let center else { return }
        guard enabled else { return center.clearResident(kind: Self.kind) }

        let decision = NextEventWindow.decide(events.map { ($0.start, $0.isAllDay) }, now: Date())

        if let index = decision.showing {
            let event = events[index]
            center.setResident(LiveActivity(
                kind: Self.kind,
                symbol: "calendar",
                tint: event.tint,
                spokenName: event.title,
                trailing: .countdown(event.start),
                size: .regular,
                duration: .infinity,
                priority: LiveActivity.Priority.scheduled
            ))
        } else {
            center.clearResident(kind: Self.kind)
        }

        guard let at = decision.recheck else { return }
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        recheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, at.timeIntervalSinceNow), execute: work)
    }
}
