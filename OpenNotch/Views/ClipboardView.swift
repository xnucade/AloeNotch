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
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var calls = CallMonitor.shared

    /// Rows show only their kind while a call is likely — see `CallMonitor`.
    private var redacted: Bool { settings.blurClipboardInCalls && calls.micInUse }

    private var visible: [ClipItem] {
        compact ? Array(clipboard.visibleItems.prefix(4)) : clipboard.visibleItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader { header }

            if clipboard.items.isEmpty {
                empty
            } else if visible.isEmpty {
                noMatches
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Metrics.Spacing.hairline) {
                        ForEach(visible) { item in
                            ClipboardRow(
                                item: item,
                                copied: justCopied == item.id,
                                compact: compact,
                                redacted: redacted,
                                pinned: clipboard.isPinned(item),
                                canPin: clipboard.canPin(item),
                                copy: { plain in copy(item, plainText: plain) },
                                togglePin: { withAnimation(Motion.contentFade) { clipboard.togglePin(item) } },
                                remove: { withAnimation(Motion.contentFade) { clipboard.remove(item) } }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(Motion.contentFade, value: clipboard.items)
        .animation(Motion.contentFade, value: clipboard.query)
    }

    /// The wide layout has room for the field beside the title; the column
    /// trades its title for the field while a search is open.
    @ViewBuilder
    private var header: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            if compact && clipboard.isSearching {
                ClipboardSearchField(clipboard: clipboard)
            } else {
                Text("Clipboard")
                    .font(Typography.micro(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.tertiary)
                Spacer()
                if !clipboard.items.isEmpty {
                    if compact {
                        ClipboardSearchButton(clipboard: clipboard)
                    } else {
                        ClipboardSearchField(clipboard: clipboard, autofocus: false)
                            .frame(maxWidth: 180)
                    }
                    ClipboardClearButton(clipboard: clipboard)
                }
            }
        }
        .frame(height: 16)
    }

    private var noMatches: some View {
        Text("No matches")
            .font(Typography.caption())
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: "doc.on.clipboard")
                .font(Typography.icon(compact ? 15 : 22, .light))
                .foregroundStyle(Ink.quaternary)
            Text("Nothing copied yet")
                .font(Typography.caption())
                .foregroundStyle(Ink.tertiary)
            if !compact {
                Text("History stays in memory and is cleared when AloeNotch quits.")
                    .font(Typography.micro())
                    .foregroundStyle(Ink.quaternary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ item: ClipItem, plainText: Bool) {
        clipboard.copy(item, plainText: plainText)
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

/// Forget everything. Shared by the list's own header and the tabbed column's.
struct ClipboardClearButton: View {
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        Button { clipboard.clear() } label: {
            Image(systemName: "trash")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Forget everything copied so far, pins included")
        .accessibilityLabel("Clear clipboard history")
    }
}

/// Opens the search field in a header too narrow to hold it permanently.
struct ClipboardSearchButton: View {
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        Button {
            withAnimation(Motion.contentFade) { clipboard.isSearching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Search the clipboard")
        .accessibilityLabel("Search clipboard history")
    }
}

/// Filters the list as you type. Esc or the X closes it and clears it.
struct ClipboardSearchField: View {
    @ObservedObject var clipboard: ClipboardManager
    /// On when the field appears because the user asked for it; off where it
    /// is always on screen and grabbing focus would steal keystrokes meant
    /// for the rest of the panel.
    var autofocus = true

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: "magnifyingglass")
                .font(Typography.icon(10, .medium))
                .foregroundStyle(Ink.tertiary)
            TextField("Search", text: $clipboard.query)
                .textFieldStyle(.plain)
                .font(Typography.caption())
                .foregroundStyle(Ink.primary)
                .focused($focused)
                .onExitCommand { close() }
            if autofocus || !clipboard.query.isEmpty {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.icon(10, .medium))
                        .foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Close search")
                .accessibilityLabel("Close search")
            }
        }
        .padding(.horizontal, Metrics.Spacing.snug)
        .frame(height: 18)
        .background(Capsule().fill(Ink.fill))
        .onAppear { if autofocus { focused = true } }
    }

    private func close() {
        withAnimation(Motion.contentFade) { clipboard.endSearch() }
        focused = false
    }
}

/// One entry. Deliberately a single line at compact size: the value of a
/// clipboard history is scanning it fast, and wrapped rows destroy that.
///
/// Click copies it back; ⌥-click copies text without its formatting. The
/// rest — plain text, pin, remove — is in the context menu, and the wide
/// layout also keeps a pin beside each row.
private struct ClipboardRow: View {
    let item: ClipItem
    let copied: Bool
    let compact: Bool
    let redacted: Bool
    let pinned: Bool
    let canPin: Bool
    let copy: (_ plainText: Bool) -> Void
    let togglePin: () -> Void
    let remove: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button {
                copy(NSEvent.modifierFlags.contains(.option))
            } label: {
                HStack(spacing: Metrics.Spacing.snug) {
                    leading

                    Text(copied ? "Copied" : shown)
                        .font(Typography.caption())
                        .foregroundStyle(copied ? .white : (redacted ? Ink.tertiary : Ink.primary))
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !compact && !copied && !redacted {
                        if case .image(let thumb, _) = item.kind {
                            // The 16pt glyph says "a picture"; this says which.
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: Metrics.artworkRadius(20), style: .continuous))
                        } else {
                            Text(item.detail)
                                .font(Typography.micro())
                                .foregroundStyle(Ink.quaternary)
                                .fixedSize()
                        }
                    }

                    if compact && pinned && !copied {
                        Image(systemName: "pin.fill")
                            .font(Typography.icon(8, .semibold))
                            .foregroundStyle(Ink.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, compact ? 8 : Metrics.Spacing.tight)
                .padding(.vertical, compact ? 5 : 7)
                .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle())
            .help(copied ? "Copied" : "Copy again: \(shown)")
            .accessibilityLabel(pinned ? "\(shown), pinned" : shown)
            .accessibilityHint("Copies it again")

            if !compact { pinSlot }
        }
        .background {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(copied ? Ink.fillBright : (hovering ? Ink.fillStrong : Ink.fill))
        }
        .contentShape(.rect(cornerRadius: Metrics.controlRadius))
        .onHover { inside in
            withAnimation(Motion.micro) {
                hovering = inside
            }
        }
        .contextMenu { menu }
        .accessibilityActions { menu }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy") { copy(false) }
        if item.hasFormatting {
            Button("Copy as Plain Text") { copy(true) }
        }
        Divider()
        if pinned {
            Button("Unpin") { togglePin() }
        } else {
            Button("Pin") { togglePin() }.disabled(!canPin)
        }
        Button("Remove", role: .destructive) { remove() }
    }

    /// Always there when pinned, so pins read as pins at a glance; on hover
    /// otherwise, so twenty-four unpinned rows don't carry twenty-four
    /// outlines of a control most of them will never use.
    private var pinSlot: some View {
        Button(action: togglePin) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(Typography.icon(10, .medium))
                .foregroundStyle(pinned ? Ink.secondary : Ink.tertiary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(pinned || (hovering && canPin) ? 1 : 0)
        .disabled(!pinned && !canPin)
        .help(pinned ? "Unpin" : "Pin — kept at the top, and never pushed out by newer copies")
        .accessibilityLabel(pinned ? "Unpin" : "Pin")
        .padding(.trailing, Metrics.Spacing.tight)
    }

    private var shown: String { redacted ? item.redactedPreview : item.preview }

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
                    // 16pt is small, but a recognisable screenshot or photo
                    // is still recognisable at 16pt.
                    .blur(radius: redacted ? 4 : 0, opaque: true)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.artworkRadius(16), style: .continuous))
            } else {
                Image(systemName: item.symbol)
                    .font(Typography.icon(11, .medium))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .frame(width: 16, height: 16)
        .animation(Motion.micro, value: copied)
        .animation(Motion.contentFade, value: redacted)
    }
}
