import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Compress and convert. Both run only when asked, write their result beside
/// the originals the way Finder does, and never touch the originals.
///
/// Off the main thread: zipping a folder of video can take a minute, and
/// the notch must keep animating while it does.
enum ShelfProcessing {
    private static let queue = DispatchQueue(label: "shelf.processing", qos: .userInitiated)

    /// Finder's Compress, by the same means — `ditto` writes the archive
    /// Finder writes, resource forks and extended attributes included.
    static func compress(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        queue.async {
            let result = makeArchive(urls)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func convert(_ url: URL, to format: ImageFormat, completion: @escaping (URL?) -> Void) {
        queue.async {
            let result = makeImage(url, format)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Work

    private static func makeArchive(_ urls: [URL]) -> URL? {
        guard let desired = ShelfOutput.archiveURL(for: urls) else { return nil }
        let fm = FileManager.default
        let out = ShelfOutput.unique(desired) { fm.fileExists(atPath: $0.path) }

        if urls.count == 1 {
            // A folder is archived as itself; a file as itself too, which
            // for ditto means *not* keeping its parent — that would wrap it
            // in the folder it came from.
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: urls[0].path, isDirectory: &isFolder)
            let keep = isFolder.boolValue ? ["--keepParent"] : []
            return ditto(["-c", "-k", "--sequesterRsrc"] + keep + [urls[0].path, out.path]) ? out : nil
        }

        // Several items, possibly from several folders: gather them in one
        // folder and archive its contents. `copyItem` clones on APFS, so the
        // gathering costs no time and no space; the folder is gone before
        // this returns.
        let staging = fm.temporaryDirectory.appendingPathComponent("AloeNotch-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for url in urls {
                let target = ShelfOutput.unique(staging.appendingPathComponent(url.lastPathComponent)) {
                    fm.fileExists(atPath: $0.path)
                }
                try fm.copyItem(at: url, to: target)
            }
        } catch {
            return nil
        }
        return ditto(["-c", "-k", "--sequesterRsrc", staging.path, out.path]) ? out : nil
    }

    private static func ditto(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Re-encodes the first frame, carrying the metadata across (orientation
    /// most of all — losing it turns every phone photo on its side).
    private static func makeImage(_ url: URL, _ format: ImageFormat) -> URL? {
        let fm = FileManager.default
        let out = ShelfOutput.unique(ShelfOutput.convertedURL(for: url, to: format)) {
            fm.fileExists(atPath: $0.path)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let destination = CGImageDestinationCreateWithURL(out as CFURL,
                                                                format.type.identifier as CFString, 1, nil)
        else { return nil }

        var options: [CFString: Any] = [:]
        if format != .png { options[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? fm.removeItem(at: out)
            return nil
        }
        return out
    }
}
