import SwiftUI
import CoreLocation
import EventKit

/// Every system permission AloeNotch can ask for, with live status and a
/// one-tap way to resolve each.
///
/// The point of gathering these on one pane is that all three are optional and
/// each disables exactly one feature. Someone wondering "why is my calendar
/// empty" should be able to find the answer here rather than guessing, and the
/// rationale is shown whether or not the permission has been asked for — the
/// moment to explain a permission is *before* it is requested.
struct PermissionsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var accessibilityTrusted = MediaKeyInterceptor.isTrusted
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var locationStatus = CLLocationManager().authorizationStatus

    /// One timer for the pane rather than one per row. Accessibility in
    /// particular has no change notification — it can only be polled — and the
    /// other two are cheap enough to re-read on the same tick.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    symbol: "hand.raised",
                    rationale: accessibilityRationale,
                    status: accessibilityTrusted ? .granted : .notDetermined,
                    action: accessibilityTrusted ? nil : { MediaKeyInterceptor.requestTrust() }
                )

                SettingsDivider()

                PermissionRow(
                    title: "Calendar",
                    symbol: "calendar",
                    rationale: calendarRationale,
                    status: status(for: calendarStatus),
                    action: calendarAction,
                    actionTitle: calendarStatus == .denied ? "Open Settings…" : "Grant…"
                )

                SettingsDivider()

                PermissionRow(
                    title: "Location",
                    symbol: "location",
                    rationale: locationRationale,
                    status: status(for: locationStatus),
                    action: locationAction,
                    actionTitle: locationStatus == .denied ? "Open Settings…" : "Grant…"
                )
            }

            SettingsSection {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("AloeNotch has no account, no analytics and no network calls except fetching the weather for your approximate location. Everything else stays on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .onReceive(poll) { _ in refresh() }
    }

    private func refresh() {
        accessibilityTrusted = MediaKeyInterceptor.isTrusted
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        locationStatus = CLLocationManager().authorizationStatus
    }

    // MARK: Rationales

    private var accessibilityRationale: String {
        accessibilityTrusted
            ? "Granted. Volume and brightness show in the notch instead of the macOS HUD."
            : "Lets AloeNotch catch the volume and brightness keys first, so it can replace the macOS HUD. Without it, macOS keeps drawing its own and AloeNotch stays out of the way."
    }

    private var calendarRationale: String {
        switch calendarStatus {
        case .fullAccess:
            "Granted. Your next event shows in the panel."
        case .denied, .restricted:
            "Denied. The calendar strip will show dates but no events until this is allowed in System Settings."
        default:
            "Shows your next event in the panel. Nothing leaves your Mac."
        }
    }

    private var locationRationale: String {
        switch locationStatus {
        case .authorized, .authorizedAlways:
            "Granted. Local conditions show in the panel header."
        case .denied, .restricted:
            "Denied. Weather stays hidden until this is allowed in System Settings."
        default:
            "Used at reduced accuracy to fetch local weather — roughly your city, not your address."
        }
    }

    // MARK: Actions

    /// A denied permission cannot be re-prompted — the system only asks once.
    /// The honest thing is to send the user to the pane that can actually
    /// change it rather than showing a button that silently does nothing.
    private var calendarAction: (() -> Void)? {
        switch calendarStatus {
        case .fullAccess:
            return nil
        case .denied, .restricted:
            return { openSettings("Privacy_Calendars") }
        default:
            return {
                EKEventStore().requestFullAccessToEvents { _, _ in
                    DispatchQueue.main.async { refresh() }
                }
            }
        }
    }

    private var locationAction: (() -> Void)? {
        switch locationStatus {
        case .authorized, .authorizedAlways:
            return nil
        case .denied, .restricted:
            return { openSettings("Privacy_LocationServices") }
        default:
            // Requesting needs a live manager; the provider owns one and will
            // prompt as soon as weather is switched on.
            return { settings.showWeather = true }
        }
    }

    private func openSettings(_ anchor: String) {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Status mapping

    private func status(for s: EKAuthorizationStatus) -> PermissionRow.Status {
        switch s {
        case .fullAccess:          .granted
        case .denied, .restricted: .denied
        default:                   .notDetermined
        }
    }

    private func status(for s: CLAuthorizationStatus) -> PermissionRow.Status {
        switch s {
        case .authorized, .authorizedAlways: .granted
        case .denied, .restricted:           .denied
        default:                             .notDetermined
        }
    }
}
