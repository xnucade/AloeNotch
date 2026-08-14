import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @ObservedObject var tray: TrayModel
    @State private var isTargeted = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shelf")
                    .font(Typography.micro(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if tray.items.count >= 2 {
                    dragAllHandle
                }
                if !tray.items.isEmpty {
                    Button { tray.clear() } label: {
                        Image(systemName: "trash")
                            .font(Typography.icon(11, .medium))
                            .foregroundStyle(.white)
                            .hoverLift(restOpacity: 0.5)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }

            content
                .frame(maxWidth: .infinity, minHeight: 62)
                .background {
                    ZStack {
                        // A fill that only exists while a file is overhead, so
                        // the well reads as *open* rather than merely outlined.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(isTargeted ? 0.10 : 0))
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(isTargeted ? 0.55 : 0.14))
                    }
                }
                // Swells very slightly toward the cursor. Small on purpose:
                // this sits inside a fixed-height panel, so anything bigger
                // would push the neighbouring columns around mid-drag.
                .scaleEffect(isTargeted && !reduceMotion ? 1.03 : 1)
                .animation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion),
                           value: isTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            let accepted = tray.handleDrop(providers)
            if accepted { Haptics.caught() }
            return accepted
        }
    }

    /// A small pill that drags every staged file out at once.
    private var dragAllHandle: some View {
        ZStack {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill").font(Typography.icon(10, .medium))
                Text("Drag all").font(Typography.micro())
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
                    .font(Typography.icon(16, .light))
                Text("Drop files here")
                    .font(Typography.caption())
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
            .animation(Motion.contentFade, value: tray.items)
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
    @Environment(\.notchReduceMotion) private var reduceMotion

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
            // Lifts toward the cursor so it reads as grabbable — this is the
            // one control here you are meant to pick up and drag.
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 5, y: 2)
            // Drag the staged file back out to Finder / another app.
            .onDrag { NSItemProvider(object: item.url as NSURL) }

            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.icon(12, .medium))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(PressableButtonStyle())
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .help(item.name)
        .onHover { hovering = $0 }
        .animation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion), value: hovering)
    }
}
