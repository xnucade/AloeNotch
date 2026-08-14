import SwiftUI

/// The expanded panel showing one module at a time, large.
///
/// The alternative to the three-column layout. Side by side, every module gets
/// roughly a third of the width and has to shrink to fit — which is why the
/// track title truncates, the calendar runs at the smallest readable size, and
/// the shelf is a 150pt sliver. Giving one module the whole panel is the single
/// biggest thing that separates a calm notch from a busy one.
///
/// The cost is real and worth being honest about: you no longer see your next
/// event and what's playing in the same glance. That is the trade, and it is
/// why this is a setting.
struct FocusedContent: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    let morph: Namespace.ID

    /// Which module is showing. Nil until first shown, then resolved
    /// contextually so the panel opens on whatever is most likely wanted.
    @State private var focus: Module?

    enum Module: String, CaseIterable, Identifiable {
        case media, calendar, shelf
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .media:    "music.note"
            case .calendar: "calendar"
            case .shelf:    "tray.full"
            }
        }
        var label: String {
            switch self {
            case .media:    "Now Playing"
            case .calendar: "Calendar"
            case .shelf:    "Shelf"
            }
        }
    }

    /// Modules the user has switched on, in a stable order.
    private var available: [Module] {
        Module.allCases.filter {
            switch $0 {
            case .media:    settings.showMedia
            case .calendar: settings.showCalendar
            case .shelf:    settings.showShelf
            }
        }
    }

    /// What to show when the panel opens: whatever is playing, else the first
    /// module that exists. Opening on a silent media pane when a calendar event
    /// is minutes away would be the wrong default.
    private var resolvedFocus: Module {
        if let focus, available.contains(focus) { return focus }
        if settings.showMedia && viewModel.media.isPlaying { return .media }
        return available.first ?? .media
    }

    var body: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            HeaderRow(viewModel: viewModel)

            Group {
                switch resolvedFocus {
                case .media:    FocusedMedia(media: viewModel.media, morph: morph)
                case .calendar: FocusedCalendar(calendar: viewModel.calendar)
                case .shelf:    TrayView(tray: viewModel.tray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keyed on the module so switching cross-fades rather than cuts,
            // without the container itself moving — the panel stays put and
            // only its contents change.
            .id(resolvedFocus)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))

            if available.count > 1 {
                switcher
            }
        }
        .foregroundStyle(.white)
    }

    /// Pills to move between modules. Only shown when there is more than one —
    /// a single-item switcher is a label pretending to be a control.
    private var switcher: some View {
        HStack(spacing: Metrics.Spacing.tight) {
            ForEach(available) { module in
                SwitcherPill(
                    module: module,
                    isActive: module == resolvedFocus,
                    accent: settings.accent
                ) {
                    withAnimation(Motion.contentFade) { focus = module }
                }
            }
        }
    }
}

private struct SwitcherPill: View {
    let module: FocusedContent.Module
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: module.symbol)
                .font(Typography.icon(12, .medium))
                .foregroundStyle(isActive ? accent : .white.opacity(hovering ? 0.85 : 0.45))
                .frame(width: 34, height: 22)
                .background {
                    Capsule().fill(.white.opacity(isActive ? 0.14 : (hovering ? 0.07 : 0)))
                }
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .help(module.label)
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

// MARK: - Media, with room

/// Now Playing given the whole panel: larger artwork, a full-width scrubber,
/// and transport controls big enough to hit without aiming.
private struct FocusedMedia: View {
    @ObservedObject var media: NowPlayingManager
    let morph: Namespace.ID

    var body: some View {
        if media.isAvailable && media.current.hasContent {
            HStack(spacing: Metrics.Spacing.loose) {
                artwork
                VStack(alignment: .leading, spacing: Metrics.Spacing.hairline) {
                    Text(media.current.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(media.current.artist)
                        .font(Typography.body())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    Spacer(minLength: Metrics.Spacing.snug)

                    if media.current.duration > 0 {
                        FocusedScrubber(media: media)
                    }
                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(Motion.contentFade, value: media.current)
        } else {
            VStack(spacing: Metrics.Spacing.tight) {
                Image(systemName: "music.note")
                    .font(Typography.icon(22, .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text(media.isAvailable ? "Nothing playing" : "Now Playing unavailable")
                    .font(Typography.body(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(media.isAvailable
                     ? "Start something in Music, Spotify or a browser."
                     : "The media helper didn't start. Relaunching AloeNotch usually fixes it.")
                    .font(Typography.caption())
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let art = media.current.artwork {
                    ZStack {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                            .id(media.current.artworkToken)
                            .transition(.opacity)
                    }
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .animation(Motion.contentFade, value: media.current.artworkToken)
                    .matchedGeometryEffect(id: NotchRootView.artworkID, in: morph)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.4)))
                        .frame(width: 82, height: 82)
                }
            }
            .frame(width: 82, height: 82)
            .background {
                if let art = media.current.artwork {
                    Image(nsImage: art)
                        .resizable().scaledToFill()
                        .frame(width: 82, height: 82)
                        .scaleEffect(1.35)
                        .blur(radius: 26)
                        .opacity(0.55)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            if let icon = media.current.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.black.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: -6, y: 6)
            }
        }
    }

    /// Bigger than the column layout's, and leading-aligned rather than
    /// centred: the eye is already at the left edge reading the title.
    private var controls: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            FocusedTransportButton(symbol: "backward.fill", size: 15) { media.previous() }
            FocusedTransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill",
                                   size: 18, prominent: true) {
                media.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            FocusedTransportButton(symbol: "forward.fill", size: 15) { media.next() }
        }
    }
}

private struct FocusedTransportButton: View {
    let symbol: String
    var size: CGFloat = 15
    var prominent = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    private var diameter: CGFloat { prominent ? 34 : 30 }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.icon(size))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.88))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(.white.opacity(prominent
                                                 ? (hovering ? 0.20 : 0.13)
                                                 : (hovering ? 0.13 : 0)))
                }
                .scaleEffect(reduceMotion ? 1 : (hovering ? 1.06 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                hovering = inside
            }
        }
    }
}

/// Full-width scrubber. Shows time remaining rather than total, which is the
/// number you actually want mid-track.
private struct FocusedScrubber: View {
    @ObservedObject var media: NowPlayingManager
    @State private var dragging = false
    @State private var dragFraction: Double = 0
    @State private var hovering = false
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = media.current.duration
            let elapsed = dragging ? dragFraction * duration : media.liveElapsed()
            let fraction = duration > 0 ? min(1, max(0, elapsed / duration)) : 0

            VStack(spacing: Metrics.Spacing.tight) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: max(2, w * fraction))
                    }
                    .frame(height: hovering || dragging ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion)) {
                            hovering = inside
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                dragging = true
                                dragFraction = min(1, max(0, g.location.x / max(1, w)))
                            }
                            .onEnded { _ in
                                media.seek(to: dragFraction * duration)
                                dragging = false
                            }
                    )
                }
                .frame(height: 10)
                .animation(.linear(duration: dragging ? 0 : 0.5), value: fraction)

                HStack {
                    Text(time(elapsed))
                    Spacer()
                    Text("-" + time(max(0, duration - elapsed)))
                }
                .font(Typography.micro(.regular))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func time(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Calendar, with room

/// The week strip plus the next few events, rather than one truncated line.
private struct FocusedCalendar: View {
    @ObservedObject var calendar: CalendarModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = context.date
            let cal = Calendar.current
            let days = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }

            HStack(alignment: .top, spacing: Metrics.Spacing.loose) {
                VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
                    Text(today, format: .dateTime.month(.wide))
                        .font(Typography.display())
                    HStack(spacing: Metrics.Spacing.tight) {
                        ForEach(days, id: \.self) { day in
                            let isToday = cal.isDate(day, inSameDayAs: today)
                            VStack(spacing: Metrics.Spacing.tight) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(Typography.micro(.semibold))
                                    .foregroundStyle(isToday ? settings.accent : .white.opacity(0.35))
                                Text(day, format: .dateTime.day())
                                    .font(Typography.body(isToday ? .bold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(isToday ? settings.accent : .white.opacity(0.65))
                            }
                            .frame(width: 24)
                        }
                    }
                }

                Divider().frame(width: 1).overlay(.white.opacity(0.12))

                VStack(alignment: .leading, spacing: Metrics.Spacing.tight) {
                    if !calendar.isAuthorized {
                        Text("Allow Calendar in Settings → Access")
                            .font(Typography.caption())
                            .foregroundStyle(.white.opacity(0.5))
                    } else if calendar.upcoming.isEmpty {
                        Text("Nothing for today")
                            .font(Typography.caption())
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        // Three events instead of one — the room exists now.
                        ForEach(calendar.upcoming.prefix(3)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.snug) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(event.tint)
                                    .frame(width: 3, height: 12)
                                Text(event.timeText)
                                    .font(Typography.micro(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 52, alignment: .leading)
                                Text(event.title)
                                    .font(Typography.caption())
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(Motion.contentFade, value: calendar.upcoming)
        }
    }
}
