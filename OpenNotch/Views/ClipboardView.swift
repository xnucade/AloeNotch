import SwiftUI

/// Recent clipboard entries. Click one to put it back on the clipboard.
///
/// The same view serves both panel layouts; `compact` only changes how many
/// rows are worth drawing and how much room each gets. Two separate views would
/// mean two places to fix every future row tweak.
struct ClipboardList: View {
    @ObservedObject var clipboard: ClipboardManager
    var compact = true
    /// Hidden when the tabbed column supplies its own header.
    var showsHeader = true

    /// The row that was just clicked, so it can confirm rather than silently
    /// doing something invisible — the clipboard has no visible state, so
    /// without this the click reads as a no-op.
    @State private var justCopied: UUID?
    @State private var resetTask: Task<Void, Never>?

    private var visible: [ClipItem] {
        compact ? Array(clipboard.items.prefix(4)) : clipboard.items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader { header }

            if clipboard.items.isEmpty {
                empty
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Metrics.Spacing.hairline) {
                        ForEach(visible) { item in
                            ClipboardRow(
                                item: item,
                                copied: justCopied == item.id,
                                compact: compact
                            ) {
                                copy(item)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(Motion.contentFade, value: clipboard.items)
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(Typography.micro(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if !clipboard.items.isEmpty {
                Button { clipboard.clear() } label: {
                    Image(systemName: "trash")
                        .font(Typography.icon(11, .medium))
                        .foregroundStyle(.white)
                        .hoverLift(restOpacity: 0.5)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Forget everything copied so far")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: "doc.on.clipboard")
                .font(Typography.icon(compact ? 15 : 22, .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing copied yet")
                .font(Typography.caption())
                .foregroundStyle(.white.opacity(0.45))
            if !compact {
                Text("History stays in memory and is cleared when AloeNotch quits.")
                    .font(Typography.micro())
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ item: ClipItem) {
        clipboard.copy(item)
        resetTask?.cancel()
        withAnimation(Motion.micro) { justCopied = item.id }
        resetTask = Task {
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(Motion.contentFade) { justCopied = nil }
            }
        }
    }
}

/// One entry. Deliberately a single line at compact size: the value of a
/// clipboard history is scanning it fast, and wrapped rows destroy that.
private struct ClipboardRow: View {
    let item: ClipItem
    let copied: Bool
    let compact: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Spacing.snug) {
                leading

                Text(copied ? "Copied" : item.preview)
                    .font(Typography.caption())
                    .foregroundStyle(.white.opacity(copied ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !compact && !copied {
                    Text(item.detail)
                        .font(Typography.micro())
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 5 : 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(copied ? 0.18 : (hovering ? 0.10 : 0.04)))
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(PressableButtonStyle())
        .help(copied ? "Copied" : "Copy again: \(item.preview)")
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }

    /// A thumbnail where there is one, the type glyph otherwise. Both occupy
    /// the same box so the text column starts at the same x on every row.
    @ViewBuilder
    private var leading: some View {
        ZStack {
            if copied {
                Image(systemName: "checkmark")
                    .font(Typography.icon(11, .semibold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if case .image(let thumb, _) = item.kind {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: item.symbol)
                    .font(Typography.icon(11, .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 16, height: 16)
        .animation(Motion.micro, value: copied)
    }
}
