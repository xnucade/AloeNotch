import AppKit
import MetricKit

/// Crash and hang reports, kept on this Mac so a bug report can include one.
///
/// macOS hands MetricKit diagnostics to the app on a later launch — usually
/// the next day — as JSON. The last few are written to Application Support
/// and nothing else happens to them: no network, no analytics. The About tab
/// offers them to the clipboard, and the person decides where they go.
final class Diagnostics: NSObject, ObservableObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    @Published private(set) var reportCount = 0

    private static let keep = 5

    private let directory: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("AloeNotch/Diagnostics", isDirectory: true)

    func start() {
        MXMetricManager.shared.add(self)
        // Anything delivered while the app wasn't subscribed yet.
        store(MXMetricManager.shared.pastDiagnosticPayloads)
        reportCount = reports().count
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        store(payloads)
        DispatchQueue.main.async { self.reportCount = self.reports().count }
    }

    private func store(_ payloads: [MXDiagnosticPayload]) {
        guard let directory, !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for payload in payloads {
            // The window's end date names the file, so a payload delivered
            // twice (live, then again as a past one) overwrites itself.
            let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
            try? payload.jsonRepresentation()
                .write(to: directory.appendingPathComponent("\(stamp).json"), options: .atomic)
        }
        for stale in reports().dropFirst(Self.keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Newest first.
    private func reports() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Plain text for an issue: what's running, then each report as-is.
    func copyReport() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var text = "AloeNotch \(version) (\(build)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        let files = reports()
        if files.isEmpty { text += "\nNo crash or hang reports on this Mac.\n" }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = String(data: data, encoding: .utf8) else { continue }
            text += "\n\(json)\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
