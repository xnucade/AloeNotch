import SwiftUI

/// The expanded panel as two pages: Home (Now Playing and the calendar) and
/// Tools (the shelf, clipboard and timer), switched from the header.
///
/// The middle ground between the other two layouts. Columns fit three modules
/// into one glance and shrink all of them; one-at-a-time gives each the whole
/// panel but parts what's playing from what's next. Here the two things you
/// glance at share a page, and the things you work with get the other.
struct PagedContent: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    let morph: Namespace.ID
    @Environment(\.notchReduceMotion) private var reduceMotion

    /// Nil until the user picks one, so the panel opens on whatever is
    /// happening rather than wherever it was left.
    @State private var chosen: Page?

    enum Page: String, CaseIterable, Identifiable {
        case home, tools
        var id: String { rawValue }

        var label: String {
            switch self {
            case .home:  String(localized: "Home")
            case .tools: String(localized: "Tools")
            }
        }
        var symbol: String {
            switch self {
            case .home:  "music.note.house"
            case .tools: "tray.full"
            }
        }
        /// Home sits on the left, Tools on the right; pages slide from
        /// their own side.
        var edge: CGFloat { self == .home ? -1 : 1 }
    }

    private var hasHome: Bool { settings.showMedia || settings.showCalendar }
    private var hasTools: Bool {
        settings.showShelf || settings.showClipboard || settings.showTimer || settings.showMirror
    }

    private var pages: [Page] {
        Page.allCases.filter { $0 == .home ? hasHome : hasTools }
    }

    /// The user's pick if it still exists. Otherwise a running timer pulls
    /// Tools forward, the same rule the other layouts follow, and Home wins.
    private var page: Page {
        if let chosen, pages.contains(chosen) { return chosen }
        if settings.showTimer && viewModel.timer.isActive { return .tools }
        return pages.first ?? .home
    }

    private var pageBinding: Binding<Page> {
        Binding(get: { page }, set: { show($0) })
    }

    var body: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            HeaderRow(viewModel: viewModel, page: pages.count > 1 ? pageBinding : nil)
                .notchEntrance(0)

            ZStack {
                switch page {
                case .home:  home.transition(slide(.home))
                case .tools: tools.transition(slide(.tools))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .notchEntrance(1)
        }
        .foregroundStyle(.white)
        // A file dragged in is headed for the shelf, so show it.
        .onChange(of: viewModel.dragReach != nil) { _, dragging in
            if dragging && settings.showShelf { show(.tools) }
        }
        // Two-finger swipe left or right on the open panel.
        .onChange(of: viewModel.moduleStep) { _, step in
            guard pages.count > 1 else { return }
            show(step.direction > 0 ? .tools : .home)
        }
    }

    private func show(_ next: Page) {
        guard next != page || chosen == nil else { return }
        withAnimation(Motion.contentFade) { chosen = next }
    }

    /// Each page slides a little from its own side as it fades, so the two
    /// read as neighbours rather than replacements. Reduce Motion: fade only.
    private func slide(_ p: Page) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 28 * p.edge))
    }

    // MARK: Pages

    @ViewBuilder
    private var home: some View {
        HStack(spacing: Metrics.Spacing.loose) {
            if settings.showMedia {
                FocusedMedia(media: viewModel.media, lyrics: viewModel.lyrics, morph: morph)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if settings.showMedia && settings.showCalendar {
                LinearGradient(colors: [.clear, Ink.fillStrong, .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 1)
            }
            if settings.showCalendar {
                // Beside the music, the week strip; alone, the roomy version
                // with the next few events.
                if settings.showMedia {
                    CalendarWeekStrip(calendar: viewModel.calendar)
                        .frame(width: 196)
                } else {
                    FocusedCalendar(calendar: viewModel.calendar)
                }
            }
        }
    }

    private var tools: some View {
        UtilityColumn(tray: viewModel.tray,
                      clipboard: viewModel.clipboard,
                      timer: viewModel.timer,
                      mirror: viewModel.mirror,
                      roomy: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Home | Tools, in the header beside the clock. A capsule slides behind the
/// active page; under Reduce Motion it moves without travelling.
struct PageSwitch: View {
    @Binding var page: PagedContent.Page
    let accent: Color
    @Namespace private var selection
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PagedContent.Page.allCases) { p in
                PageSwitchSegment(
                    page: p,
                    isActive: p == page,
                    accent: accent,
                    selection: selection,
                    slides: !reduceMotion
                ) { page = p }
            }
        }
        .padding(2)
        .background(Capsule().fill(Ink.fill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page")
    }
}

private struct PageSwitchSegment: View {
    let page: PagedContent.Page
    let isActive: Bool
    let accent: Color
    let selection: Namespace.ID
    let slides: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: page.symbol)
                    .font(Typography.icon(10, .medium))
                Text(page.label)
                    .font(Typography.micro(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(isActive ? accent : (hovering ? Ink.primary : Ink.tertiary))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background {
                if isActive && slides {
                    Capsule()
                        .fill(Ink.fillStrong)
                        .matchedGeometryEffect(id: "page", in: selection)
                } else if isActive {
                    Capsule().fill(Ink.fillStrong)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .help(page.label)
        .accessibilityLabel(page.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { inside in
            withAnimation(Motion.micro) { hovering = inside }
        }
    }
}
