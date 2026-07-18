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
                if !tray.items.isEmpty {
                    Button { tray.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }

            content
                .frame(maxWidth: .infinity, minHeight: 74)
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
