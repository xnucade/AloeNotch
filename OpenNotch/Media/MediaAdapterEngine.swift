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
            let engine = try? MediaAdapterEngine()
            let ok = engine?.runTest() ?? false
            DispatchQueue.main.async { completion(ok ? engine : nil) }
        }
    }

    private init() throws {
        guard let resources = Bundle.main.resourceURL,
              let script = Self.locate("mediaremote-adapter.pl", under: resources),
              let lib = Self.locate("MediaRemoteAdapterLib.dat", under: resources)
        else {
            throw CocoaError(.fileNoSuchFile)
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

    private func runTest() -> Bool {
        let test = Process()
        test.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        test.arguments = [scriptURL.path, frameworkURL.path, "test"]
        test.standardOutput = FileHandle.nullDevice
        test.standardError = FileHandle.nullDevice
        do { try test.run() } catch { return false }
        test.waitUntilExit()
        return test.terminationStatus == 0
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
        p.terminationHandler = { [weak self] _ in
            // Relaunch after a beat if the stream dies while we still want it.
            guard let self else { return }
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
