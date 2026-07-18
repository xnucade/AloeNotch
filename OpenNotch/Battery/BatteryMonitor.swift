import Foundation
import IOKit.ps
import Combine

/// Reads battery state from IOKit power sources and republishes it on the main
/// thread. Uses the IOKit run-loop notification so updates arrive when the
/// charge level or power source actually changes, with a slow timer as backup.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Double = 1.0     // 0...1
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isPresent = true

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?

    // The IOKit callback holds an unretained pointer to self, so the source
    // must be torn down before this object goes away.
    deinit {
        stop()
    }

    func start() {
        refresh()

        // IOKit callback fires on any power-source change.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            isPresent = false
            return
        }

        isPresent = true

        if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
           let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            level = Double(capacity) / Double(max)
        }

        let state = desc[kIOPSPowerSourceStateKey] as? String
        isPluggedIn = (state == kIOPSACPowerValue)
        isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
    }
}
