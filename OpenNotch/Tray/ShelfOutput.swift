import Foundation
import UniformTypeIdentifiers

/// Where a shelf action's result goes and what it is called, with no file
/// system attached. Follows Finder exactly, because that is what people will
/// compare it to: "Report.pdf.zip" for one item, "Archive.zip" for several,
/// and " 2", " 3" before the extension rather than overwriting anything.
enum ShelfOutput {
    /// The archive Finder's Compress would make for these items, in the
    /// folder of the first.
    static func archiveURL(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let folder = first.deletingLastPathComponent()
        let name = urls.count == 1 ? first.lastPathComponent + ".zip" : "Archive.zip"
        return folder.appendingPathComponent(name)
    }

    /// The same image in another format, beside the original.
    static func convertedURL(for url: URL, to format: ImageFormat) -> URL {
        url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    /// `desired`, or the first of "Name 2.ext", "Name 3.ext"… that is free.
    /// A double extension like ".pdf.zip" is kept whole, as Finder does.
    static func unique(_ desired: URL, exists: (URL) -> Bool) -> URL {
        guard exists(desired) else { return desired }
        let folder = desired.deletingLastPathComponent()
        let name = desired.lastPathComponent
        let ext = desired.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 2
        while true {
            let candidate = folder.appendingPathComponent(
                ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}

/// The formats a shelf image can be converted to. Three because those are
/// the ones anyone asks for: PNG to keep it lossless, JPEG for anything
/// that will be uploaded, HEIC for size.
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .png:  "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:  "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var type: UTType {
        switch self {
        case .png:  .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    /// The formats worth offering for a file — every one except the one it
    /// already is. Empty for anything that isn't an image.
    static func targets(for url: URL) -> [ImageFormat] {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else { return [] }
        return allCases.filter { !type.conforms(to: $0.type) }
    }
}
