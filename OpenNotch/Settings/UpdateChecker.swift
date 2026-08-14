import Foundation
import AppKit
import Combine

/// Asks GitHub whether a newer release exists.
///
/// Deliberately not Sparkle. AloeNotch already publishes every release to
/// GitHub with the DMG attached, so the release list *is* the appcast — no feed
/// to host, no signing keys to manage, and nothing to keep in sync with the
/// releases that already exist. The cost is that this only tells you an update
/// is there; installing it is still a download and a drag.
///
/// It is also deliberately quiet. It checks at most once a day, never
/// interrupts, and surfaces the result in Settings and the menu bar rather
/// than in front of whatever you were doing.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// A newer release, with the page to send the user to.
        case available(version: String, url: URL)
        /// Network failure, rate limit, unparseable response — all the same to
        /// the user, who can only try again later.
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Latest version seen, kept so the menu bar can show a dot without
    /// re-checking on every open.
    @Published private(set) var availableVersion: String?

    private let releasesURL = URL(string:
        "https://api.github.com/repos/xnucade/AloeNotch/releases/latest")!
    private let releasesPage = URL(string:
        "https://github.com/xnucade/AloeNotch/releases/latest")!

    private var settings: AppSettings { .shared }

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - Entry points

    /// Called at launch. Does nothing if the user has switched checking off or
    /// one has already run today — a launch-at-login app can start several
    /// times a day and none of those are new information.
    func checkIfDue() {
        guard settings.checkForUpdates else { return }
        let last = settings.lastUpdateCheck
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        Task { await check(userInitiated: false) }
    }

    /// The "Check Now" button. Runs regardless of the daily window, because the
    /// user just asked.
    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    func openReleasesPage() {
        if case .available(_, let url) = state {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(releasesPage)
        }
    }

    // MARK: - The check

    private func check(userInitiated: Bool) async {
        if case .checking = state { return }
        state = .checking

        var request = URLRequest(url: releasesURL)
        // GitHub rejects requests without one, and the version makes the
        // traffic identifiable if it ever needs explaining.
        request.setValue("AloeNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Short: this runs at launch and must never hold anything up.
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("No response from GitHub.")
                return
            }
            guard http.statusCode == 200 else {
                // 403 is almost always the unauthenticated rate limit (60/hour
                // per IP), which is not worth explaining in those terms.
                state = .failed(http.statusCode == 403
                    ? "GitHub is rate-limiting; try again later."
                    : "GitHub returned \(http.statusCode).")
                return
            }

            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                state = .failed("Couldn't read the release list.")
                return
            }

            // Tags are "v0.8.3"; the bundle version is "0.8.3".
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init) ?? releasesPage

            settings.lastUpdateCheck = Date()

            if SemanticVersion.compare(latest, currentVersion) > 0 {
                availableVersion = latest
                state = .available(version: latest, url: page)
            } else {
                availableVersion = nil
                state = .upToDate
            }
        } catch {
            // Offline is the common case and not worth alarming anyone about.
            state = .failed(userInitiated
                ? "Couldn't reach GitHub. Check your connection."
                : "")
        }
    }
}
