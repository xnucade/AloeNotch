import SwiftUI

/// The panel's third column: the shelf, the clipboard and the timer, as tabs.
///
/// Tabs rather than columns because a fourth and fifth column at the default
/// 680pt width would cost legibility in all of them. One click reaches the
/// other tool; there is no width at which five columns are readable.
///
/// With only one tool enabled there are no tabs at all, just that tool with its
/// own header — a switcher with one option is a label pretending to be a
/// control.
struct UtilityColumn: View {
    @ObservedObject var tray: TrayModel
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var timer: TimerModel
    @ObservedObject private var settings = AppSettings.shared

    /// Nil until the user picks one, so the column can open on whatever is
    /// actually happening rather than always on the shelf.
    @State private var tab: Tool?

    enum Tool: String, CaseIterable, Identifiable {
        case shelf, clipboard, timer
        var id: String { rawValue }

        var label: String {
            switch self {
            case .shelf:     "Shelf"
            case .clipboard: "Clipboard"
            case .timer:     "Timer"
            }
        }
        var symbol: String {
            switch self {
            case .shelf:     "tray.full"
            case .clipboard: "doc.on.clipboard"
            case .timer:     "timer"
            }
        }
    }

    private var tools: [Tool] {
        Tool.allCases.filter {
            switch $0 {
            case .shelf:     settings.showShelf
            case .clipboard: settings.showClipboard
            case .timer:     settings.showTimer
            }
        }
    }

    /// What to show. The user's choice if they made one and it still exists,
    /// otherwise a running timer, otherwise the first tool.
    ///
    /// Opening the panel onto the shelf while a countdown is ticking would put
    /// the one live thing behind a click — and the fallback also covers a tool
    /// being switched off in Settings while the panel is open, which would
    /// otherwise leave an empty column.
    private var active: Tool {
        if let tab, tools.contains(tab) { return tab }
        if timer.isActive && tools.contains(.timer) { return .timer }
        return tools.first ?? .shelf
    }

    var body: some View {
        if tools.count <= 1 {
            if let only = tools.first { pane(only, showsHeader: true) }
        } else {
            VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
                switcher
                pane(active, showsHeader: false)
            }
            // A timer started while you are looking at another tab pulls its
            // own forward. Anything you just started is the thing you want.
            .onChange(of: timer.isActive) { _, running in
                guard running, settings.showTimer else { return }
                withAnimation(Motion.contentFade) { tab = .timer }
            }
        }
    }

    @ViewBuilder
    private func pane(_ tool: Tool, showsHeader: Bool) -> some View {
        switch tool {
        case .shelf:
            TrayView(tray: tray, showsHeader: showsHeader)
        case .clipboard:
            ClipboardList(clipboard: clipboard, compact: true, showsHeader: showsHeader)
        case .timer:
            TimerView(timer: timer, compact: true, showsHeader: showsHeader)
        }
    }

    /// Sits exactly where each pane's own title would, in the same micro-caps
    /// style — so switching tools doesn't shift anything below it by a pixel.
    ///
    /// Only the active tab spells its name out; the others are their glyph
    /// alone. Three full labels do not fit in a 160pt column, and shrinking all
    /// three to fit would make the one that matters as hard to read as the two
    /// that don't.
    private var switcher: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            ForEach(tools) { t in
                UtilityTab(tool: t,
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

    /// The active pane's controls, hoisted into the switcher row. Leaving them
    /// in the pane would mean two rows of chrome above a 62pt list.
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
        case .timer:
            if timer.isActive { TimerCancelButton { timer.cancel() } }
        }
    }
}

private struct UtilityTab: View {
    let tool: UtilityColumn.Tool
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private var tint: Color {
        isActive ? accent : .white.opacity(hovering ? 0.7 : 0.38)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .font(Typography.icon(11, .medium))
                if isActive {
                    Text(tool.label)
                        .font(Typography.micro(.semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(tint)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .help(tool.label)
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}
