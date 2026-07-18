import SwiftUI
import Combine
import CoreImage

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage? = nil
    /// Dominant artwork color, punched up for use as the ambient rim glow.
    var accent: Color? = nil
    /// Track length in seconds (0 when unknown / live streams). Stable per
    /// track, so it doesn't churn `current`; elapsed time is interpolated
    /// separately via `liveElapsed()`.
    var duration: Double = 0

    var hasContent: Bool { !title.isEmpty || !artist.isEmpty }
}

/// Publishes the system's current now-playing track and forwards transport
/// commands. Prefers the perl-based MediaAdapterEngine (works on macOS 15.4+
/// and covers browsers, so YouTube shows up too); falls back to the direct
/// MediaRemote bridge on older systems where it still functions. If neither
/// works the UI shows a friendly placeholder.
final class NowPlayingManager: ObservableObject {
    @Published private(set) var current = NowPlaying()
    @Published private(set) var isPlaying = false
    @Published private(set) var isAvailable = false

    private let bridge = MediaRemoteBridge.shared
    private var adapter: MediaAdapterEngine?
    private var observers: [NSObjectProtocol] = []

    // Stream payloads repeat the same artwork many times per track; decode and
    // color-analyze only when it actually changes.
    private var artworkCacheKey: String?
    private var cachedArtwork: NSImage?
    private var cachedAccent: Color?

    // Elapsed-time interpolation: the source reports elapsed only every ~150ms,
    // so we advance it locally between updates from the last known value.
    private var elapsedBase: Double = 0
    private var elapsedCapturedAt = Date()
    private var playbackRate: Double = 0

    func start() {
        MediaAdapterEngine.probe { [weak self] engine in
            guard let self else { return }
            if let engine {
                self.adapter = engine
                self.isAvailable = true
                engine.onUpdate = { [weak self] payload in self?.apply(payload) }
                engine.startStream()
            } else {
                self.startLegacyBridge()
            }
        }
    }

    func stop() {
        adapter?.stop()
        adapter = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Transport

    func togglePlayPause() {
        if let adapter {
            adapter.send(.togglePlayPause)
        } else {
            bridge.send(.togglePlayPause)
            refreshPlaying()
        }
    }

    func next() {
        if let adapter { adapter.send(.nextTrack) } else { bridge.send(.nextTrack) }
    }

    func previous() {
        if let adapter { adapter.send(.previousTrack) } else { bridge.send(.previousTrack) }
    }

    /// Interpolated current playback position, in seconds. Read this from a
    /// TimelineView so the progress bar advances smoothly between updates.
    func liveElapsed() -> Double {
        guard current.duration > 0 else { return 0 }
        let advance = playbackRate > 0 ? Date().timeIntervalSince(elapsedCapturedAt) * playbackRate : 0
        return min(current.duration, max(0, elapsedBase + advance))
    }

    /// Seek to a position in seconds (adapter path only; the legacy bridge has
    /// no seek). Updates the local estimate immediately for a responsive bar.
    func seek(to seconds: Double) {
        elapsedBase = max(0, seconds)
        elapsedCapturedAt = Date()
        adapter?.seek(toSeconds: seconds)
    }

    // MARK: - Adapter path

    private func apply(_ payload: [String: Any]) {
        var np = NowPlaying()
        np.title = payload["title"] as? String ?? ""
        np.artist = payload["artist"] as? String ?? ""
        np.album = payload["album"] as? String ?? ""

        if let base64 = payload["artworkData"] as? String {
            if base64 != artworkCacheKey {
                artworkCacheKey = base64
                if let data = Data(base64Encoded: base64),
                   let image = NSImage(data: data) {
                    cachedArtwork = image
                    cachedAccent = Self.accentColor(from: image)
                } else {
                    cachedArtwork = nil
                    cachedAccent = nil
                }
            }
            np.artwork = cachedArtwork
            np.accent = cachedAccent
        } else {
            artworkCacheKey = nil
            cachedArtwork = nil
            cachedAccent = nil
        }

        // Browser sources (YouTube etc.) often have a title but no artist;
        // show the app's name in that slot so the row doesn't look broken.
        if np.artist.isEmpty, !np.title.isEmpty,
           let bundleID = payload["bundleIdentifier"] as? String {
            np.artist = Self.displayName(forBundleID: bundleID)
        }

        np.duration = payload["duration"] as? Double ?? 0

        let playing = (payload["playing"] as? NSNumber)?.boolValue ?? false
        // Capture the elapsed baseline so liveElapsed() can advance from it.
        elapsedBase = payload["elapsedTime"] as? Double ?? 0
        elapsedCapturedAt = Date()
        let rate = payload["playbackRate"] as? Double ?? 0
        playbackRate = playing ? (rate > 0 ? rate : 1) : 0

        current = np
        isPlaying = playing
    }

    /// Average color of the artwork via CIAreaAverage, with saturation and
    /// brightness floors so muddy averages still glow nicely against black.
    private static func accentColor(from image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: ciImage,
                  kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let base = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        ).usingColorSpace(.deviceRGB) ?? .white

        // Near-gray artwork (common for video thumbnails) has no meaningful
        // hue — boosting its saturation would pick a random color. Let it glow
        // soft white instead; only punch up colors that are actually there.
        let saturation = base.saturationComponent
        let boosted = NSColor(
            hue: base.hueComponent,
            saturation: saturation < 0.15 ? saturation : max(saturation, 0.55),
            brightness: max(base.brightnessComponent, 0.7),
            alpha: 1
        )
        return Color(nsColor: boosted)
    }

    private static func displayName(forBundleID bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let name = Bundle(url: url)?
               .object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleID
    }

    // MARK: - Legacy bridge path (pre-15.4 macOS)

    private func startLegacyBridge() {
        isAvailable = bridge.isAvailable
        guard isAvailable else { return }

        bridge.registerForNotifications()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: MediaRemoteBridge.infoDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshInfo() })

        observers.append(center.addObserver(
            forName: MediaRemoteBridge.isPlayingDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshPlaying() })

        refreshInfo()
        refreshPlaying()
    }

    private func refreshInfo() {
        bridge.fetchNowPlayingInfo { [weak self] info in
            guard let self else { return }
            var np = NowPlaying()
            np.title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            np.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            np.album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
               let image = NSImage(data: data) {
                np.artwork = image
                np.accent = Self.accentColor(from: image)
            }
            np.duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
            self.elapsedBase = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
            self.elapsedCapturedAt = Date()
            let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            self.playbackRate = rate
            self.current = np
        }
    }

    private func refreshPlaying() {
        bridge.fetchIsPlaying { [weak self] playing in
            self?.isPlaying = playing
        }
    }
}
