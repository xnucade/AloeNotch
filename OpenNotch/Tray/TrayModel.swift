import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct TrayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumbnail: NSImage?

    var name: String { url.lastPathComponent }
}

/// Holds files the user has dropped onto the notch for temporary staging.
/// Items live only for the session; nothing is copied or moved on disk.
final class TrayModel: ObservableObject {
    @Published private(set) var items: [TrayItem] = []

    func add(urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(TrayItem(url: url, thumbnail: nil))
            generateThumbnail(for: url) { [weak self] image in
                guard let self, let idx = self.items.firstIndex(where: { $0.url == url }) else { return }
                self.items[idx].thumbnail = image
            }
        }
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() { items.removeAll() }

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
