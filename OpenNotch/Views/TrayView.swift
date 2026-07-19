import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @ObservedObject var tray: TrayModel
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shelf")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if tray.items.count >= 2 {
                    dragAllHandle
                }
                if !tray.items.isEmpty {
                    Button { tray.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }

            content
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .foregroundStyle(.white.opacity(isTargeted ? 0.55 : 0.14))
                        .animation(.smooth(duration: 0.2), value: isTargeted)
                )
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            tray.handleDrop(providers)
        }
    }

    /// A small pill that drags every staged file out at once.
    private var dragAllHandle: some View {
        ZStack {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9))
                Text("Drag all").font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08), in: Capsule())
            // Transparent AppKit drag source sits on top and initiates the
            // multi-item drag session (SwiftUI's .onDrag is single-item only).
            MultiFileDragHandle(urls: tray.items.map(\.url))
        }
        .fixedSize()
        .help("Drag all \(tray.items.count) files out together")
    }

    @ViewBuilder
    private var content: some View {
        if tray.items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 16))
                Text("Drop files here")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(tray.items) { item in
                    TrayChip(item: item) { tray.remove(item) }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(6)
            .animation(.snappy(duration: 0.3), value: tray.items)
        }
    }

}

/// Wraps an AppKit drag source that begins a dragging session containing every
/// staged file as its own dragging item — so dropping the handle onto Finder or
/// another app deposits all of them at once.
private struct MultiFileDragHandle: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.urls = urls
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.urls = urls
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []

        override func mouseDown(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            let items: [NSDraggingItem] = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                // Fan the icons out a little so the drag reads as a stack.
                let o = CGFloat(i) * 5
                item.setDraggingFrame(CGRect(x: o, y: -o, width: 28, height: 28), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }
}

private struct TrayChip: View {
    let item: TrayItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            // Drag the staged file back out to Finder / another app.
            .onDrag { NSItemProvider(object: item.url as NSURL) }

            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .help(item.name)
        .onHover { hovering = $0 }
    }
}
