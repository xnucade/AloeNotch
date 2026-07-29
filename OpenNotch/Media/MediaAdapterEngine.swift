import Foundation

/// Runs the vendored mediaremote-adapter (see ThirdParty/MediaRemoteAdapter/)
/// to read system-wide now-playing data on macOS 15.4+, where the MediaRemote
/// APIs are no longer directly accessible to third-party apps. `/usr/bin/perl`
/// carries an Apple bundle identifier and is therefore entitled; we spawn it
/// with the adapter script and consume line-delimited JSON from stdout.
///
/// Covers every app that publishes to the system now-playing center: Apple
/// Music, Spotify, YouTube in a browser, Podcasts, VLC, etc.
final class MediaAdapterEngine {
    /// Called on the main thread with each payload. An empty dictionary means
    /// nothing is playing.
    var onUpdate: (([String: Any]) -> Void)?

    private let scriptURL: URL
    private let frameworkURL: URL
    private var process: Process?
    private var stdoutBuffer = Data()
    private var isRunning = false

    // MARK: - Setup

    /// Locates the vendored resources, installs the framework layout the perl
    /// script expects, and verifies entitlement — all off the main thread.
    /// Calls back on main with a ready engine, or nil if unsupported.
    static func probe(_ completion: @escaping (MediaAdapterEngine?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let engine: MediaAdapterEngine
            do {
                engine = try MediaAdapterEngine()
            } catch {
                NSLog("AloeNotch: Now Playing unavailable — adapter setup failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if let reason = engine.selfTestFailure() {
                NSLog("AloeNotch: Now Playing unavailable — \(reason)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(engine) }
        }
    }

    /// Why setup failed, in terms that name the actual missing piece. The old
    /// blanket `CocoaError(.fileNoSuchFile)` could not distinguish a missing
    /// script from a missing library from an un-writable Application Support.
    enum SetupError: LocalizedError {
        case noResourceBundle
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .noResourceBundle:
                "the app bundle has no Resources directory"
            case .missingResource(let name):
                "bundled resource '\(name)' is missing from Resources"
            }
        }
    }

    private init() throws {
        guard let resources = Bundle.main.resourceURL else {
            throw SetupError.noResourceBundle
        }
        guard let script = Self.locate("mediaremote-adapter.pl", under: resources) else {
            throw SetupError.missingResource("mediaremote-adapter.pl")
        }
        guard let lib = Self.locate("MediaRemoteAdapterLib.dat", under: resources) else {
            throw SetupError.missingResource("MediaRemoteAdapterLib.dat")
        }
        self.scriptURL = script
        self.frameworkURL = try Self.installFramework(from: lib)
    }

    /// Finds a resource regardless of whether Xcode flattened the folder.
    private static func locate(_ name: String, under root: URL) -> URL? {
        let direct = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    /// The perl script requires `<dir>/Name.framework/Name`; build that layout
    /// in Application Support from the flat resource dylib.
    private static func installFramework(from lib: URL) throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("AloeNotch/MediaRemoteAdapter.framework", isDirectory: true)
        let binary = dir.appendingPathComponent("MediaRemoteAdapter")

        let libAttrs = try fm.attributesOfItem(atPath: lib.path)
        let installedAttrs = try? fm.attributesOfItem(atPath: binary.path)
        let upToDate = (installedAttrs?[.size] as? Int) == (libAttrs[.size] as? Int)

        if !upToDate {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.removeItem(at: binary)
            try fm.copyItem(at: lib, to: binary)
        }
        return dir
    }

    /// Runs the adapter's self-test. `nil` means it passed; otherwise a
    /// human-readable reason.
    ///
    /// This is the single point where Now Playing silently switches itself off,
    /// and it used to discard both the exit status and stderr — so when it
    /// failed, the UI said "unavailable" forever with nothing anywhere to
    /// explain why. Whatever perl complained about is worth surfacing.
    private func selfTestFailure() -> String? {
        let test = Process()
        test.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        test.arguments = [scriptURL.path, frameworkURL.path, "test"]
        test.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        test.standardError = errors

        do {
            try test.run()
        } catch {
            return "could not launch /usr/bin/perl: \(error.localizedDescription)"
        }

        // Drain before waiting: the pipe has a finite buffer, and a chatty
        // failure could otherwise block the child forever on write while we
        // block on exit.
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        test.waitUntilExit()
        guard test.terminationStatus != 0 else { return nil }

        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = message.isEmpty ? "no error output" : message
        return """
            adapter self-test exited \(test.terminationStatus) — \(detail)
              script: \(scriptURL.path)
              framework: \(frameworkURL.path)
            """
    }

    // MARK: - Streaming

    func startStream() {
        guard !isRunning else { return }
        isRunning = true
        sweepOrphans()
        launchStream()
    }

    /// Kills stream processes left behind by a previous run that didn't exit
    /// cleanly (force-quit, crash). Matches on our Application Support path,
    /// which appears in the perl command line — nothing else matches it.
    private func sweepOrphans() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "AloeNotch/MediaRemoteAdapter.framework"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    func stop() {
        isRunning = false
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    private func launchStream() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, frameworkURL.path,
                       "stream", "--no-diff", "--debounce=150"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }
        p.terminationHandler = { [weak self] proc in
            // Relaunch after a beat if the stream dies while we still want it.
            guard let self else { return }
            if self.isRunning {
                NSLog("AloeNotch: media adapter stream exited (status \(proc.terminationStatus)) — restarting in 2s")
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if self.isRunning { self.launchStream() }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            isRunning = false
            NSLog("AloeNotch: failed to launch media adapter stream: \(error)")
        }
    }

    /// Accumulates stdout and emits one payload per complete JSON line.
    /// Only ever called from the pipe's readability handler, which FileHandle
    /// serializes, so the buffer needs no extra locking.
    private func ingest(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newline)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            guard
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                object["type"] as? String == "data"
            else { continue }
            let payload = object["payload"] as? [String: Any] ?? [:]
            DispatchQueue.main.async { [weak self] in self?.onUpdate?(payload) }
        }
    }

    // MARK: - Commands

    /// MediaRemote command IDs (same codes MRMediaRemoteSendCommand uses).
    enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    func send(_ command: Command) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, frameworkURL.path,
                       "send", String(command.rawValue)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Seek to a timeline position. The adapter's `seek` takes MICROSECONDS
    /// (payload elapsed/duration are in seconds), so convert here.
    func seek(toSeconds seconds: Double) {
        let micros = Int((max(0, seconds) * 1_000_000).rounded())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptURL.path, frameworkURL.path, "seek", String(micros)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
