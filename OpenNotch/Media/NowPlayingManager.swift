import SwiftUI
import Combine
import CoreImage

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage? = nil
    /// Stable identity for whatever is in `artwork`.
    ///
    /// `NSImage` is a class, so `NowPlaying`'s synthesised `==` compares it by
    /// reference — useless for asking "is this a different cover?". Views need
    /// that question answered to crossfade between tracks, so this carries a
    /// hash of the source bytes instead. It changes only when the picture does.
    var artworkToken: Int? = nil
    /// Icon of the app the audio is coming from (Music, Spotify, browser…).
    var sourceIcon: NSImage? = nil
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
    /// Payload string we have most recently *started* decoding — the dedupe guard.
    private var artworkCacheKey: String?
    private var cachedArtwork: NSImage?
    private var cachedAccent: Color?
    /// Token of the artwork actually in `cachedArtwork`. Trails
    /// `artworkCacheKey` while a decode is in flight, so the token always
    /// describes the image currently on screen rather than the one arriving.
    private var cachedArtworkToken: Int?
    private var cachedSourceBundleID: String?
    private var cachedSourceIcon: NSImage?

    /// Artwork decoding and colour analysis run here, never on main.
    private let artworkQueue = DispatchQueue(label: "com.kadeslab.AloeNotch.artwork",
                                             qos: .userInitiated)
    /// Guards against an older, slower decode landing after a newer one.
    private var artworkGeneration = 0

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
                decodeArtwork(base64)
            }
            // Whatever is decoded *now*. On a track change this is still the
            // previous cover for a frame or two, which is what makes the
            // crossfade possible — the old image holds until the new one is
            // ready, rather than blanking and popping back in.
            np.artwork = cachedArtwork
            np.accent = cachedAccent
            np.artworkToken = cachedArtworkToken
        } else {
            artworkCacheKey = nil
            cachedArtwork = nil
            cachedAccent = nil
            cachedArtworkToken = nil
        }

        // Source app: browser sources (YouTube etc.) often have a title but no
        // artist, so show the app's name there; also grab its icon for a badge.
        if let bundleID = payload["bundleIdentifier"] as? String {
            if np.artist.isEmpty, !np.title.isEmpty {
                np.artist = Self.displayName(forBundleID: bundleID)
            }
            if bundleID != cachedSourceBundleID {
                cachedSourceBundleID = bundleID
                cachedSourceIcon = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: bundleID)
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
            np.sourceIcon = cachedSourceIcon
        } else {
            cachedSourceBundleID = nil
            cachedSourceIcon = nil
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

    /// Decode a cover and derive its accent colour off the main thread, then
    /// publish both together.
    ///
    /// This used to happen inline in `apply`, which runs on main: every track
    /// change did a full image decode plus a Core Image reduction before the
    /// run loop could draw again. That is precisely the moment the panel wants
    /// to be animating a crossfade and easing the glow to a new colour, so the
    /// one frame it most needed was the one being blocked.
    private func decodeArtwork(_ base64: String) {
        artworkGeneration &+= 1
        let generation = artworkGeneration
        let token = base64.hashValue

        artworkQueue.async { [weak self] in
            let image = Data(base64Encoded: base64).flatMap { NSImage(data: $0) }
            let accent = image.flatMap { Self.accentColor(from: $0) }

            DispatchQueue.main.async {
                guard let self, self.artworkGeneration == generation else {
                    return   // a newer cover already won
                }
                self.cachedArtwork = image
                self.cachedAccent = accent
                self.cachedArtworkToken = image == nil ? nil : token

                // Republish so the new cover reaches the UI. Everything else in
                // `current` is already up to date from the payload that started
                // this decode.
                var updated = self.current
                updated.artwork = image
                updated.accent = accent
                updated.artworkToken = self.cachedArtworkToken
                self.current = updated
            }
        }
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
                np.artworkToken = data.hashValue
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
