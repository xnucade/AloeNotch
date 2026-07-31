import Foundation
import AppKit
import EventKit
import CoreLocation
import Combine

/// Owns the objects that ask for system permissions, and publishes their status.
///
/// The owning part is the entire point. Both of these APIs require the
/// requesting object to still be alive when the user answers the prompt:
///
///   - `EKEventStore().requestFullAccessToEvents { … }` creates a store that is
///     released the instant the statement returns, taking the pending request
///     with it. The prompt either never appears or the callback never fires.
///   - `CLLocationManager` delivers its result through a delegate, so a manager
///     created inline has no delegate and nothing to deliver to.
///
/// Both were written the throwaway way in the Settings and onboarding panes,
/// which is why neither Grant button did anything. One long-lived owner fixes
/// both and gives the UI a single place to read status from.
final class PermissionRequester: NSObject, ObservableObject {
    static let shared = PermissionRequester()

    @Published private(set) var calendarStatus: EKAuthorizationStatus
    @Published private(set) var locationStatus: CLAuthorizationStatus

    /// Retained deliberately — see the note above.
    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()

    private override init() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    // MARK: Requests

    /// Prompts for calendar access. Does nothing once granted — the system only
    /// ever asks once, so a second call on a denied status is silently ignored
    /// and the UI should offer System Settings instead.
    func requestCalendar() {
        guard calendarStatus != .fullAccess else { return }
        eventStore.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func requestLocation() {
        guard locationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    /// Re-read both. Cheap, and the only way to notice an Accessibility-style
    /// change made outside the app.
    func refresh() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        locationStatus = locationManager.authorizationStatus
    }

    // MARK: Convenience

    var calendarGranted: Bool { calendarStatus == .fullAccess }

    var locationGranted: Bool {
        locationStatus == .authorized || locationStatus == .authorizedAlways
    }

    /// Denied means the system will not prompt again; the only route is the
    /// Privacy pane in System Settings.
    static func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension PermissionRequester: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.locationStatus = manager.authorizationStatus
        }
    }
}
