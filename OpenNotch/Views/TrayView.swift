import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @ObservedObject var tray: TrayModel
    /// Hidden when the column supplies its own header — the tabbed
    /// "Collected" column shows the tab pills where this title would be.
    var showsHeader = true
    @State private var isTargeted = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader { headerRow }

            content
                .frame(maxWidth: .infinity, minHeight: 62)
                .background {
                    ZStack {
                        // A fill that only exists while a file is overhead, so
                        // the well reads as *open* rather than merely outlined.
                        RoundedRectangle(cornerRadius: Metrics.wellRadius, style: .continuous)
                            .fill(isTargeted ? Ink.fill : .clear)
                        RoundedRectangle(cornerRadius: Metrics.wellRadius, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(isTargeted ? Ink.tertiary : Ink.fillStrong)
                    }
                }
                // Swells very slightly toward the cursor. Small on purpose:
                // this sits inside a fixed-height panel, so anything bigger
                // would push the neighbouring columns around mid-drag.
                .scaleEffect(isTargeted && !reduceMotion ? 1.03 : 1)
                .animation(Motion.micro,
                           value: isTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            let accepted = tray.handleDrop(providers)
            if accepted { Haptics.caught() }
            return accepted
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Shelf")
                .font(Typography.micro(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Ink.tertiary)
            Spacer()
            if tray.items.count >= 2 {
                TrayDragAllPill(tray: tray)
            }
            if !tray.items.isEmpty {
                TrayAirDropButton(urls: tray.items.map(\.url))
            }
            if !tray.items.isEmpty {
                TrayClearButton { tray.clear() }
            }
        }
    }

}

/// A small pill that drags every staged file out at once. Its own type so the
/// tabbed column can host it in place of the shelf's header.
struct TrayDragAllPill: View {
    @ObservedObject var tray: TrayModel

    private var urls: [URL] { tray.items.map(\.url) }

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill").font(Typography.icon(10, .medium))
                Text("Drag all").font(Typography.micro())
            }
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Ink.fill, in: Capsule())
            // Transparent AppKit drag source sits on top and initiates the
            // multi-item drag session (SwiftUI's .onDrag is single-item only).
            ShelfDragSource(urls: urls, dragSize: 28) { tray.draggedOut(urls) }
        }
        .fixedSize()
        .help("Drag all \(urls.count) files out together")
        .contextMenu {
            Button("Compress \(urls.count) Items", systemImage: "archivebox") { tray.compress(urls) }
        }
    }
}

/// The shelf's trash button, shared with the tabbed column's header.
/// Sends everything on the shelf over AirDrop in one go.
struct TrayAirDropButton: View {
    let urls: [URL]

    var body: some View {
        Button { ShelfActions.airDrop(urls) } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help(urls.count == 1 ? "AirDrop this file" : "AirDrop all \(urls.count) files")
        .accessibilityLabel("AirDrop")
    }
}

struct TrayClearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Empty the shelf")
        .accessibilityLabel("Empty the shelf")
    }
}

extension TrayView {

    @ViewBuilder
    private var content: some View {
        if tray.items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                    .font(Typography.icon(16, .light))
                Text("Drop files here")
                    .font(Typography.caption())
            }
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(tray.items) { item in
                    TrayChip(item: item, tray: tray)
                        // Arrives a size too big and settles into its slot on
                        // the arrival spring, as if shrinking in from the
                        // dragged icon; leaves the quiet way.
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .scale(scale: 1.5)
                                .combined(with: .opacity)
                                .animation(Motion.arrival),
                            removal: .scale(scale: 0.6).combined(with: .opacity)
                        ))
                }
            }
            .padding(Metrics.wellPadding)
            .animation(Motion.contentFade, value: tray.items)
        }
    }

}

/// An AppKit drag source laid transparently over a tile or the drag-all
/// pill.
///
/// AppKit rather than SwiftUI's `.onDrag` for two things SwiftUI can't do: a
/// session carrying several files at once, and hearing how a drag ended —
/// which is what lets the shelf empty itself after a successful drop. A
/// click that never becomes a drag is handed back as `onClick`.
struct ShelfDragSource: NSViewRepresentable {
    let urls: [URL]
    /// What the pointer carries for a single file; its Finder icon otherwise.
    var image: NSImage?
    var dragSize: CGFloat = 44
    var onClick: (() -> Void)?
    let onDraggedOut: () -> Void

    func makeNSView(context: Context) -> SourceView {
        let v = SourceView()
        update(v)
        return v
    }

    func updateNSView(_ nsView: SourceView, context: Context) { update(nsView) }

    private func update(_ v: SourceView) {
        v.urls = urls
        v.image = image
        v.dragSize = dragSize
        v.onClick = onClick
        v.onDraggedOut = onDraggedOut
    }

    final class SourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var image: NSImage?
        var dragSize: CGFloat = 44
        var onClick: (() -> Void)?
        var onDraggedOut: () -> Void = {}

        private var pressed: NSEvent?

        /// Right- and control-clicks fall through to the SwiftUI context
        /// menu underneath; everything else is this view's.
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent,
               event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                return nil
            }
            return super.hitTest(point)
        }

        /// The panel is rarely key; the first click on a tile should act,
        /// not merely focus.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            pressed = event
            // The drag-all pill has nothing to click; it starts at once,
            // as it always has.
            if onClick == nil { beginDrag(from: event) }
        }

        /// A few points of travel before a press becomes a drag, so a
        /// slightly unsteady click still opens Quick Look.
        override func mouseDragged(with event: NSEvent) {
            guard let pressed else { return }
            let dx = event.locationInWindow.x - pressed.locationInWindow.x
            let dy = event.locationInWindow.y - pressed.locationInWindow.y
            guard dx * dx + dy * dy > 9 else { return }
            beginDrag(from: pressed)
        }

        override func mouseUp(with event: NSEvent) {
            guard pressed != nil else { return }
            pressed = nil
            onClick?()
        }

        private func beginDrag(from event: NSEvent) {
            pressed = nil
            guard !urls.isEmpty else { return }
            let items: [NSDraggingItem] = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = urls.count == 1 ? (image ?? NSWorkspace.shared.icon(forFile: url.path))
                                           : NSWorkspace.shared.icon(forFile: url.path)
                // Fan the icons out a little so the drag reads as a stack.
                let o = CGFloat(i) * 5
                item.setDraggingFrame(CGRect(x: o, y: -o, width: dragSize, height: dragSize), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        /// A drop back onto the notch itself is not "out" — the shelf would
        /// otherwise drop the file it was just handed back.
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            guard !operation.isEmpty else { return }
            if let window, window.frame.contains(screenPoint) { return }
            onDraggedOut()
        }
    }
}

private struct TrayChip: View {
    let item: TrayItem
    @ObservedObject var tray: TrayModel

    /// Every staged file, so Quick Look's arrow keys walk the whole shelf.
    private var all: [URL] { tray.items.map(\.url) }
    private var isWorking: Bool { tray.working.contains(item.url) }
    private var conversions: [ImageFormat] { ImageFormat.targets(for: item.url) }

    private func quickLook() {
        ShelfActions.quickLook(all, startingAt: all.firstIndex(of: item.url) ?? 0)
    }
    private func remove() { tray.remove(item) }

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: Metrics.wellItemRadius, style: .continuous).fill(Ink.fill)
                }
            }
            .frame(width: 44, height: 44)
            .overlay {
                // Dims and spins while a compress or convert reads it, so
                // the beep or the new tile has something to answer.
                if isWorking {
                    ZStack {
                        Color.black.opacity(0.45)
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.wellItemRadius, style: .continuous))
            // Lifts toward the cursor so it reads as grabbable — this is the
            // one control here you are meant to pick up and drag.
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 5, y: 2)
            // Drag the staged file back out to Finder / another app; a
            // plain click previews it instead.
            .overlay {
                ShelfDragSource(urls: [item.url], image: item.thumbnail, onClick: quickLook) {
                    tray.draggedOut([item.url])
                }
            }

            if hovering {
                Button(action: remove) {
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
        // The remove badge only exists under the pointer, which VoiceOver
        // doesn't have; the same action lives on the tile instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAction(named: "Quick Look", quickLook)
        .accessibilityAction(named: "AirDrop") { ShelfActions.airDrop([item.url]) }
        .accessibilityAction(named: "Compress") { tray.compress([item.url]) }
        .accessibilityAction(named: "Remove from shelf", remove)
        .contextMenu {
            Button("Quick Look", systemImage: "eye", action: quickLook)
            Button("AirDrop…", systemImage: "dot.radiowaves.left.and.right") { ShelfActions.airDrop([item.url]) }
            Button("Show in Finder", systemImage: "folder") { ShelfActions.revealInFinder([item.url]) }
            Divider()
            Button("Compress", systemImage: "archivebox") { tray.compress([item.url]) }
                .disabled(isWorking)
            if !conversions.isEmpty {
                Menu("Convert to") {
                    ForEach(conversions) { format in
                        Button(format.label) { tray.convert(item.url, to: format) }
                    }
                }
                .disabled(isWorking)
            }
            if all.count >= 2 {
                Button("Compress All \(all.count) Items", systemImage: "archivebox") { tray.compress(all) }
            }
            Divider()
            Button("Remove from Shelf", systemImage: "xmark", role: .destructive, action: remove)
        }
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .animation(Motion.contentFade, value: isWorking)
    }
}
