import SwiftUI
import Combine
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
    @ObservedObject private var permissions = PermissionRequester.shared

    /// Accessibility has no change notification and can only be polled. The
    /// other two publish through `PermissionRequester`, so this timer exists
    /// solely for that one value.
    @State private var accessibilityTrusted = MediaKeyInterceptor.isTrusted
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    symbol: "hand.raised",
                    rationale: accessibilityTrusted
                        ? "Granted. Volume and brightness show in the notch instead of the macOS HUD."
                        : "Lets AloeNotch catch the volume and brightness keys first, so it can replace the macOS HUD. Without it, macOS keeps drawing its own and AloeNotch stays out of the way.",
                    status: accessibilityTrusted ? .granted : .notDetermined,
                    action: accessibilityTrusted ? nil : { MediaKeyInterceptor.requestTrust() }
                )

                SettingsDivider()

                PermissionRow(
                    title: "Calendar",
                    symbol: "calendar",
                    rationale: calendarRationale,
                    status: status(for: permissions.calendarStatus),
                    action: calendarAction,
                    actionTitle: permissions.calendarStatus == .denied ? "Open Settings…" : "Grant…"
                )

                SettingsDivider()

                PermissionRow(
                    title: "Location",
                    symbol: "location",
                    rationale: locationRationale,
                    status: status(for: permissions.locationStatus),
                    action: locationAction,
                    actionTitle: permissions.locationStatus == .denied ? "Open Settings…" : "Grant…"
                )
            }

            SettingsSection {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("AloeNotch has no account and no analytics. It makes two kinds of network request: fetching the weather for your approximate location, and asking GitHub once a day whether a newer release exists. Both can be switched off. Everything else stays on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .onReceive(poll) { _ in
            accessibilityTrusted = MediaKeyInterceptor.isTrusted
            permissions.refresh()
        }
    }

    // MARK: Rationales

    private var calendarRationale: String {
        switch permissions.calendarStatus {
        case .fullAccess:
            "Granted. Your next event shows in the panel."
        case .denied, .restricted:
            "Denied. macOS won't ask again, so this has to be changed in System Settings → Privacy & Security → Calendars."
        default:
            "Shows your next event in the panel. Nothing leaves your Mac."
        }
    }

    private var locationRationale: String {
        switch permissions.locationStatus {
        case .authorized, .authorizedAlways:
            "Granted. Local conditions show in the panel header."
        case .denied, .restricted:
            "Denied. macOS won't ask again, so this has to be changed in System Settings → Privacy & Security → Location Services."
        default:
            "Used at reduced accuracy to fetch local weather — roughly your city, not your address."
        }
    }

    // MARK: Actions

    private var calendarAction: (() -> Void)? {
        switch permissions.calendarStatus {
        case .fullAccess:
            nil
        case .denied, .restricted:
            { PermissionRequester.openPrivacySettings("Privacy_Calendars") }
        default:
            { permissions.requestCalendar() }
        }
    }

    private var locationAction: (() -> Void)? {
        switch permissions.locationStatus {
        case .authorized, .authorizedAlways:
            nil
        case .denied, .restricted:
            { PermissionRequester.openPrivacySettings("Privacy_LocationServices") }
        default:
            { permissions.requestLocation() }
        }
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
