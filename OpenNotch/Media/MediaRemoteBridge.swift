import Foundation
import AppKit

/// Thin dynamic bridge to the private MediaRemote framework.
///
/// IMPORTANT: MediaRemote is a private Apple framework. On macOS 15.4 and later
/// Apple restricted the now-playing read APIs for third-party apps, so
/// `isAvailable` may be false even though the symbols load. The rest of the app
/// checks `isAvailable` and degrades gracefully (shows a placeholder) rather
/// than crashing. This exists so the feature works where the OS still allows it.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    // C function signatures we need.
    private typealias GetNowPlayingInfo =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlaying =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    // Takes the dispatch queue notifications should be delivered on.
    private typealias RegisterForNotifications =
        @convention(c) (DispatchQueue) -> Void
    private typealias SendCommand =
        @convention(c) (Int, [AnyHashable: Any]?) -> Bool

    private var handle: UnsafeMutableRawPointer?
    private var getInfo: GetNowPlayingInfo?
    private var getIsPlaying: GetIsPlaying?
    private var registerFn: RegisterForNotifications?
    private var sendCommandFn: SendCommand?

    /// Command codes understood by MRMediaRemoteSendCommand.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Notification names posted by MediaRemote after `registerForNotifications`.
    static let infoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    private(set) var isAvailable = false

    private init() {
        load()
    }

    private func load() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        self.handle = handle

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        getInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        registerFn = sym("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterForNotifications.self)
        sendCommandFn = sym("MRMediaRemoteSendCommand", as: SendCommand.self)

        isAvailable = (getInfo != nil && sendCommandFn != nil)
    }

    func registerForNotifications() {
        registerFn?(.main)
    }

    func fetchNowPlayingInfo(_ completion: @escaping ([String: Any]) -> Void) {
        guard let getInfo else { completion([:]); return }
        getInfo(.main, completion)
    }

    func fetchIsPlaying(_ completion: @escaping (Bool) -> Void) {
        guard let getIsPlaying else { completion(false); return }
        getIsPlaying(.main, completion)
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }
}
