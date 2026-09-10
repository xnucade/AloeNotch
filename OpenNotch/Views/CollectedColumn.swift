import SwiftUI

/// The panel's third column: the shelf and the clipboard, as two tabs.
///
/// They are one column rather than two because they are the same idea — things
/// you have set aside — and because a fourth column at the default 680pt width
/// would leave every column too narrow to read. Tabbing costs one click to
/// reach the other list; a fourth column would cost legibility in all four.
///
/// With only one of the two enabled there are no tabs, just that list with its
/// own header. A switcher with one option is a label pretending to be a control.
struct CollectedColumn: View {
    @ObservedObject var tray: TrayModel
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var tab: Tab = .shelf

    enum Tab: String, CaseIterable, Identifiable {
        case shelf, clipboard
        var id: String { rawValue }
        var label: String { self == .shelf ? "Shelf" : "Clipboard" }
    }

    private var tabs: [Tab] {
        var t: [Tab] = []
        if settings.showShelf { t.append(.shelf) }
        if settings.showClipboard { t.append(.clipboard) }
        return t
    }

    /// Falls back to whichever tab still exists, so turning a module off in
    /// Settings while the panel is open doesn't leave an empty column.
    private var active: Tab { tabs.contains(tab) ? tab : (tabs.first ?? .shelf) }

    var body: some View {
        if tabs.count <= 1 {
            single
        } else {
            VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
                switcher
                pane(active, showsHeader: false)
            }
        }
    }

    @ViewBuilder
    private var single: some View {
        if let only = tabs.first {
            pane(only, showsHeader: true)
        }
    }

    @ViewBuilder
    private func pane(_ tab: Tab, showsHeader: Bool) -> some View {
        switch tab {
        case .shelf:
            TrayView(tray: tray, showsHeader: showsHeader)
        case .clipboard:
            ClipboardList(clipboard: clipboard, compact: true, showsHeader: showsHeader)
        }
    }

    /// Sits exactly where each pane's own title would, in the same micro-caps
    /// style — so switching tabs doesn't shift anything below it by a pixel.
    private var switcher: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            ForEach(tabs) { t in
                CollectedTab(title: t.label,
                             isActive: t == active,
                             accent: settings.accent) {
                    withAnimation(Motion.contentFade) { tab = t }
                }
            }
            Spacer(minLength: Metrics.Spacing.tight)
            actions
        }
        .frame(height: 16)
    }

    /// The active pane's controls, hoisted up into the switcher row. Leaving
    /// them in the pane would mean two rows of chrome above a 62pt list.
    @ViewBuilder
    private var actions: some View {
        switch active {
        case .shelf:
            if tray.items.count >= 2 { TrayDragAllPill(urls: tray.items.map(\.url)) }
            if !tray.items.isEmpty { TrayClearButton { tray.clear() } }
        case .clipboard:
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
}

private struct CollectedTab: View {
    let title: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.micro(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(isActive ? accent : .white.opacity(hovering ? 0.7 : 0.38))
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}
