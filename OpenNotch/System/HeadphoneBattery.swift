import Foundation
import CoreBluetooth
import IOBluetooth

/// AirPods and Beats battery for the "connected" announcement. Opt-in.
///
/// Two hazards shape this:
///
/// - **Permission.** Touching IOBluetooth without Bluetooth access doesn't
///   fail, it terminates the app (TCC treats it as a privacy violation). So
///   nothing here calls into IOBluetooth unless CoreBluetooth reports access
///   as granted, and the prompt is only ever raised from the settings toggle.
/// - **Private API.** The battery properties aren't public. Each is checked
///   with `responds(to:)` before it's read, so an OS that drops one degrades
///   to the plain "connected" announcement instead of an exception.
final class HeadphoneBattery: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = HeadphoneBattery()

    @Published private(set) var authorization = CBManager.authorization

    var isAuthorized: Bool { authorization == .allowedAlways }

    /// Held only to raise the prompt and hear the answer.
    private var central: CBCentralManager?

    func requestAccess() {
        guard authorization == .notDetermined, central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBManager.authorization
        if authorization != .notDetermined { self.central = nil }
    }

    /// The levels of the connected Bluetooth device called `name` — the
    /// audio output's name is the headset's Bluetooth name. Nil when access
    /// isn't granted, no such device is connected, or it reports nothing.
    func reading(forDeviceNamed name: String) -> HeadphoneBatteryReading? {
        guard isAuthorized,
              let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let device = devices.first(where: { $0.isConnected() && $0.name == name })
        else { return nil }

        func level(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            return (device.value(forKey: key) as? NSNumber)?.intValue
        }
        let reading = HeadphoneBatteryReading(
            left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"),
            caseLevel: level("batteryPercentCase"),
            single: level("batteryPercentSingle") ?? level("batteryPercentCombined")
        )
        return reading.isEmpty ? nil : reading
    }
}
