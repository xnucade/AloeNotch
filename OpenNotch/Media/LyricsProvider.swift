import Foundation
import Combine

/// Synced lyrics for the current track, from LRCLIB. Opt-in.
///
/// This is the second thing that can leave the Mac (after weather): with
/// lyrics on, the track's title, artist, album and length go to lrclib.net —
/// a free, open lyrics database with no account and no key. Nothing else is
/// sent, one request per track, and nothing at all while the setting is off.
final class LyricsProvider: ObservableObject {
    /// Lyrics for the track playing now; nil while loading, when it has none,
    /// or when the setting is off.
    @Published private(set) var lyrics: SyncedLyrics?

    private struct Track: Hashable {
        let title: String, artist: String, album: String, duration: Int
    }

    private var cancellables = Set<AnyCancellable>()
    private var task: URLSessionDataTask?
    private var playing: Track?
    /// A miss is cached as nil, so replaying a song LRCLIB doesn't have
    /// doesn't ask again. Bounded: a day of shuffle is hundreds of tracks,
    /// and only the recent ones are likely to come round again.
    private var cache: [Track: SyncedLyrics?] = [:]
    private var cacheOrder: [Track] = []
    private static let cacheLimit = 64

    private func remember(_ lyrics: SyncedLyrics?, for track: Track) {
        if cache.updateValue(lyrics, forKey: track) == nil { cacheOrder.append(track) }
        if cacheOrder.count > Self.cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        // LRCLIB asks clients to identify themselves.
        config.httpAdditionalHeaders = ["User-Agent": "AloeNotch/\(version) (https://aloenotch.com)"]
        return URLSession(configuration: config)
    }()

    func attach(to media: NowPlayingManager) {
        media.$current
            .combineLatest(AppSettings.shared.$showLyrics)
            .map { np, on -> Track? in
                guard on, !np.title.isEmpty, !np.artist.isEmpty else { return nil }
                return Track(title: np.title, artist: np.artist, album: np.album,
                             duration: Int(np.duration.rounded()))
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.load($0) }
            .store(in: &cancellables)
    }

    private func load(_ track: Track?) {
        task?.cancel()
        playing = track
        guard let track else { lyrics = nil; return }
        if let cached = cache[track] { lyrics = cached; return }
        lyrics = nil
        fetch(track, exact: true)
    }

    /// `/api/get` first: an exact match on all four fields, lengths within a
    /// couple of seconds. Streams and browser tabs often lack an album or a
    /// length, so a miss falls back to `/api/search` on title and artist.
    private func fetch(_ track: Track, exact: Bool) {
        var parts = URLComponents(string: "https://lrclib.net/api/\(exact ? "get" : "search")")!
        var query = [URLQueryItem(name: "track_name", value: track.title),
                     URLQueryItem(name: "artist_name", value: track.artist)]
        if exact {
            query.append(URLQueryItem(name: "album_name", value: track.album))
            query.append(URLQueryItem(name: "duration", value: String(track.duration)))
        }
        parts.queryItems = query
        guard let url = parts.url else { return }

        task = Self.session.dataTask(with: url) { [weak self] data, response, error in
            if (error as? URLError)?.code == .cancelled { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let found = data.flatMap { Self.parse($0, near: track.duration) }
            DispatchQueue.main.async {
                guard let self, self.playing == track else { return }
                if found == nil, exact, !track.album.isEmpty || track.duration > 0, status != 0 {
                    self.fetch(track, exact: false)
                    return
                }
                // Only remember real answers; a network failure retries next play.
                if status == 200 || status == 404 { self.remember(found, for: track) }
                self.lyrics = found
            }
        }
        task?.resume()
    }

    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
    }

    private static func parse(_ data: Data, near duration: Int) -> SyncedLyrics? {
        let decoder = JSONDecoder()
        if let one = try? decoder.decode(Record.self, from: data) {
            return one.syncedLyrics.flatMap(SyncedLyrics.init(lrc:))
        }
        guard let many = try? decoder.decode([Record].self, from: data) else { return nil }
        // Search results: the first synced one whose length is close, when
        // the length is known — a live cut or a remix won't line up.
        return many.lazy
            .filter { duration == 0 || abs(($0.duration ?? 0) - Double(duration)) <= 3 }
            .compactMap { $0.syncedLyrics.flatMap(SyncedLyrics.init(lrc:)) }
            .first
    }
}
