import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct TrayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumbnail: NSImage?

    var name: String { url.lastPathComponent }
}

/// Holds files the user has dropped onto the notch. The item *references*
/// persist across launches via file bookmarks (which survive moves/renames);
/// the files themselves are never copied or moved.
final class TrayModel: ObservableObject {
    @Published private(set) var items: [TrayItem] = []

    private let defaults = UserDefaults.standard
    private let storeKey = "shelfBookmarks"

    init() {
        restore()
    }

    func add(urls: [URL]) {
        var added = false
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(TrayItem(url: url, thumbnail: nil))
            added = true
            generateThumbnail(for: url) { [weak self] image in
                guard let self, let idx = self.items.firstIndex(where: { $0.url == url }) else { return }
                self.items[idx].thumbnail = image
            }
        }
        if added { persist() }
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    /// Shared drop handler used by the tray grid and the collapsed notch strip.
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            found = true
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self?.add(urls: [url]) }
            }
        }
        return found
    }

    // MARK: - Persistence

    private func persist() {
        let bookmarks = items.compactMap { try? $0.url.bookmarkData() }
        defaults.set(bookmarks, forKey: storeKey)
    }

    /// Restore staged files from saved bookmarks, dropping any that have since
    /// been deleted. `add(urls:)` re-persists, so stale entries are pruned.
    private func restore() {
        guard let bookmarks = defaults.array(forKey: storeKey) as? [Data] else { return }
        var urls: [URL] = []
        for data in bookmarks {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        add(urls: urls)
    }

    private func generateThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let size = CGSize(width: 80, height: 80)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            DispatchQueue.main.async {
                completion(rep?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path))
            }
        }
    }
}
