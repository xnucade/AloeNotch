// Tests for where shelf actions put their results.

import Foundation

func testShelfOutput() {
    let docs = URL(fileURLWithPath: "/Users/x/Documents")
    let report = docs.appendingPathComponent("Report.pdf")
    let folder = docs.appendingPathComponent("Project")
    let other = URL(fileURLWithPath: "/Users/x/Desktop/shot.png")

    expect(ShelfOutput.archiveURL(for: [])  == nil, "nothing to compress, no archive")
    expect(ShelfOutput.archiveURL(for: [report])?.lastPathComponent == "Report.pdf.zip",
           "one file keeps its extension inside the archive name, as Finder does")
    expect(ShelfOutput.archiveURL(for: [folder])?.lastPathComponent == "Project.zip", "a folder zips to its name")
    expect(ShelfOutput.archiveURL(for: [report, other]) == docs.appendingPathComponent("Archive.zip"),
           "several items make Archive.zip in the first one's folder")

    let taken: Set<String> = ["/Users/x/Documents/Report.pdf.zip", "/Users/x/Documents/Report.pdf 2.zip"]
    let exists = { (u: URL) in taken.contains(u.path) }
    expect(ShelfOutput.unique(docs.appendingPathComponent("Free.zip"), exists: exists).lastPathComponent == "Free.zip",
           "a free name is used as is")
    expect(ShelfOutput.unique(docs.appendingPathComponent("Report.pdf.zip"), exists: exists).lastPathComponent
           == "Report.pdf 3.zip", "a taken name counts up before the last extension")
    let bare: Set<String> = ["/Users/x/Documents/README"]
    expect(ShelfOutput.unique(docs.appendingPathComponent("README"), exists: { bare.contains($0.path) })
           .lastPathComponent == "README 2", "names without an extension count up too")

    expect(ShelfOutput.convertedURL(for: other, to: .jpeg).lastPathComponent == "shot.jpg", "conversion swaps the extension")
    expect(ImageFormat.targets(for: other) == [.jpeg, .heic], "a PNG offers the other two formats")
    expect(ImageFormat.targets(for: URL(fileURLWithPath: "/a/b.JPG")) == [.png, .heic], "extensions match case-insensitively")
    expect(ImageFormat.targets(for: URL(fileURLWithPath: "/a/b.tiff")).count == 3, "other image types offer all three")
    expect(ImageFormat.targets(for: report).isEmpty, "a PDF isn't offered image conversion")
    expect(ImageFormat.targets(for: folder).isEmpty, "nor is a folder")
}
