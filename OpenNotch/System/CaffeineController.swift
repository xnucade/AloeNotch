import IOKit.pwr_mgt
import Combine
import AppKit

/// Keeps the Mac awake while it is on.
///
/// The classic one-switch utility, and a natural fit for a panel that is
/// already open: the alternatives are a separate menu bar app, a terminal
/// command, or changing a system setting you then have to remember to change
/// back.
///
/// Holds an `IOPMAssertion`, which needs no permission and — importantly — is
/// released automatically if the app crashes or is force quit. A Mac left
/// permanently awake by a dead process would be a genuinely bad thing to leave
/// behind.
final class CaffeineController: ObservableObject {
    @Published private(set) var isActive = false

    /// Set when the user asked for a timed session, so the UI can say when it
    /// ends rather than only that it is on.
    @Published private(set) var until: Date?

    private var assertion: IOPMAssertionID = 0
    private var expiry: DispatchWorkItem?

    /// Prevents *display* sleep rather than just idle sleep. Someone keeping
    /// their Mac awake to watch a dashboard, a long render or a download wants
    /// the screen to stay on; preventing only system sleep would leave them
    /// looking at a black screen and concluding the switch is broken.
    private static let type = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString

    deinit { release() }

    /// Toggle indefinitely.
    func toggle() {
        isActive ? stop() : start(for: nil)
    }

    /// `duration` nil keeps it awake until switched off.
    func start(for duration: TimeInterval?) {
        release()

        var id: IOPMAssertionID = 0
        let reason = "AloeNotch is keeping this Mac awake" as CFString
        let status = IOPMAssertionCreateWithName(Self.type,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason, &id)
        guard status == kIOReturnSuccess else {
            NSLog("AloeNotch: could not create a power assertion (status \(status)).")
            return
        }
        assertion = id
        isActive = true

        if let duration {
            until = Date().addingTimeInterval(duration)
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            expiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        } else {
            until = nil
        }
    }

    func stop() {
        release()
        isActive = false
        until = nil
    }

    private func release() {
        expiry?.cancel()
        expiry = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}
