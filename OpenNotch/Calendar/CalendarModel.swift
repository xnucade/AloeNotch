import SwiftUI
import EventKit
import Combine

struct UpcomingEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let tint: Color

    var timeText: String {
        if isAllDay { return "All day" }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

/// Publishes the next few calendar events (coming 24 hours). Requires calendar
/// access; when denied the UI shows nothing rather than nagging.
final class CalendarModel: ObservableObject {
    @Published private(set) var upcoming: [UpcomingEvent] = []
    @Published private(set) var isAuthorized = false

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthorized = granted
                guard granted, self.isRunning else { return }
                self.beginObserving()
                self.refresh()
            }
        }
    }

    func stop() {
        isRunning = false
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        changeObserver = nil
        timer?.invalidate()
        timer = nil
        upcoming = []
    }

    private func beginObserving() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }

        // Periodic refresh so past events fall off the list.
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let start = Date()
        let end = start.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let events = self.store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .prefix(3)
                .map { event in
                    UpcomingEvent(
                        id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "Untitled",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        tint: Color(nsColor: event.calendar?.color ?? .systemBlue)
                    )
                }
            DispatchQueue.main.async { self.upcoming = Array(events) }
        }
    }
}
