import Foundation
import AppKit
import Combine
import Sparkle

/// Finds and installs new versions, through Sparkle.
///
/// The feed is `appcast.xml` on aloenotch.com (`SUFeedURL` in Info.plist),
/// written by `release.sh` and signed with the release EdDSA key; Sparkle
/// refuses any update whose signature doesn't match `SUPublicEDKey`. It
/// sends nothing but its version in the User-Agent: system profiling is off
/// in Info.plist and stays off.
///
/// It is also deliberately quiet, as the GitHub check it replaced was. A
/// scheduled check that finds something never puts a window in front of
/// whatever you were doing: it lights the menu-bar row and the Settings row
/// (Sparkle's "gentle reminders"), and Sparkle's own update window only
/// appears when you click one of them. Nothing installs without that click.
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// A newer version, waiting for the user to ask for it.
        case available(version: String)
        /// Network failure, a bad feed — all the same to the user, who can
        /// only try again later. Empty when the check ran in the background.
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Latest version seen, kept so the menu bar can show its row without
    /// re-checking on every open.
    @Published private(set) var availableVersion: String?

    private var settings: AppSettings { .shared }
    private var controller: SPUStandardUpdaterController!
    private var userInitiated = false
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: self)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - Entry points

    /// Called at launch. Starts Sparkle's scheduler, which checks at most once
    /// a day (`SUScheduledCheckInterval`) and only while the setting is on.
    func checkIfDue() {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = settings.checkForUpdates
        settings.$checkForUpdates
            .dropFirst()
            .removeDuplicates()
            .sink { updater.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
        controller.startUpdater()
    }

    /// The "Check Now" button. Runs regardless of the schedule, because the
    /// user just asked, and Sparkle reports the result in its own window.
    func checkNow() {
        userInitiated = true
        state = .checking
        controller.checkForUpdates(nil)
    }

    /// "Get It…" and the menu's "Update to…": bring up Sparkle's window for
    /// the update a quiet check already found.
    func installUpdate() {
        userInitiated = true
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

// MARK: - Sparkle

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.availableVersion = version
            self.state = .available(version: version)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.availableVersion = nil
            self.state = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: (any Error)?) {
        Task { @MainActor in
            defer { self.userInitiated = false }
            guard let error = error as NSError? else {
                self.settings.lastUpdateCheck = Date()
                return
            }
            // "No update" and "the user closed the window" arrive as errors
            // too; neither is a failure.
            let benign: Set<Int> = [Int(SUError.noUpdateError.rawValue),
                                    Int(SUError.installationCanceledError.rawValue)]
            if error.domain == SUSparkleErrorDomain, benign.contains(error.code) {
                self.settings.lastUpdateCheck = Date()
                if case .checking = self.state { self.state = .upToDate }
                return
            }
            // Offline is the common case and not worth alarming anyone about.
            self.state = .failed(self.userInitiated
                ? String(localized: "Couldn't reach aloenotch.com. Check your connection.")
                : "")
        }
    }
}

extension UpdateChecker: SPUStandardUserDriverDelegate {
    /// A menu-bar app has no window to come forward with, so scheduled
    /// updates are announced in the menu and Settings instead.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in
            self.availableVersion = version
            self.state = .available(version: version)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            // Dismissed without installing: the update is still there, and
            // the next scheduled check will light the rows again.
            if case .checking = self.state { self.state = .idle }
        }
    }
}
