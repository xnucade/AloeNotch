import SwiftUI

/// The whole notch surface. Collapsed it is a thin black strip that blends into
/// the hardware notch (with small "wings" for glanceable indicators); expanded
/// it drops down into a rounded panel with the clock, weather, media controls,
/// drop shelf, calendar, and battery.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var isDropTargeted = false

    private var metrics: NotchMetrics? { viewModel.metrics }

    private var collapsedSize: CGSize {
        metrics?.collapsedSize ?? NotchGeometry.simulatedNotchSize
    }
    private var hasHardwareNotch: Bool {
        metrics?.hasHardwareNotch ?? false
    }
    private var expandedWidth: CGFloat { metrics?.expandedWidth ?? 616 }
    private var expandedHeight: CGFloat { metrics?.expandedHeight ?? 208 }

    var body: some View {
        VStack(spacing: 0) {
            notchSurface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notchSurface: some View {
        ZStack {
            background

            Group {
                if viewModel.isExpanded {
                    ExpandedContent(viewModel: viewModel)
                        .padding(.horizontal, 18)
                        .padding(.top, collapsedSize.height + 6) // clear the physical notch
                        .padding(.bottom, 13)
                        .transition(.blurReplace.combined(with: .opacity))
                } else if !hasHardwareNotch {
                    // Indicators only make sense on the simulated strip; behind
                    // a hardware notch they'd be invisible anyway.
                    CollapsedContent(media: viewModel.media, battery: viewModel.battery)
                        .padding(.horizontal, 14)
                        .transition(.blurReplace.combined(with: .opacity))
                }
            }
            // Keep inner light effects (artwork glow etc.) inside the panel —
            // without this they bleed out into the transparent window margin.
            .clipShape(NotchShape(cornerRadius: viewModel.isExpanded ? 26 : 10))
        }
        .frame(
            width: viewModel.isExpanded ? expandedWidth : collapsedSize.width,
            height: viewModel.isExpanded ? expandedHeight : collapsedSize.height
        )
        .contentShape(Rectangle())
        .onHover { viewModel.hoverChanged($0) }
        // Dragging a file over the collapsed strip opens the shelf; dropping
        // directly on the strip stages it immediately.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            viewModel.tray.handleDrop(providers)
        }
        .onChange(of: isDropTargeted) { _, targeted in
            viewModel.hoverChanged(targeted || viewModel.isExpanded)
        }
    }

    // The window has `NotchMetrics.shadowMargin` of transparent room on the
    // sides and bottom, so the shadow can blur out fully instead of being
    // clipped into corner artifacts. Keep its extent (radius + y offset) well
    // inside that margin.
    private var background: some View {
        // 26pt expanded radius (Tahoe-era curvature); inner cards derive their
        // radii concentrically from this minus their inset.
        let radius: CGFloat = viewModel.isExpanded ? 26 : 10
        return NotchShape(cornerRadius: radius)
            .fill(.black)
            .background {
                // Ambient mode: the album art, clipped to the panel silhouette
                // and blurred, spills colored light out past the frame. The
                // window's shadow margin gives the bleed room to render.
                if settings.ambientGlow {
                    AmbientGlow(
                        media: viewModel.media,
                        radius: radius,
                        isExpanded: viewModel.isExpanded
                    )
                }
            }
            .overlay {
                // Hairline edge on the sides and bottom only. Nothing light may
                // touch the top region: the fill must stay pure black there so
                // the hardware notch cutout is indistinguishable from the panel.
                if viewModel.isExpanded {
                    NotchEdgeShape(cornerRadius: radius)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }
            }
            // Deliberately no .shadow(): its gaussian tail reaches the window
            // boundary and clips into a visible block on bright wallpapers.
            // Edge definition comes from the hairline stroke and, when music
            // plays, the ambient line.
    }
}

/// "Ambient mode": a thin line of the artwork's dominant color hugging the
/// panel's silhouette (sides and bottom), with only a small soft bloom. Total
/// spread is under ~15pt — nowhere near the window boundary, so it can never
/// clip into a block.
private struct AmbientGlow: View {
    @ObservedObject var media: NowPlayingManager
    let radius: CGFloat
    let isExpanded: Bool

    var body: some View {
        if media.isPlaying, let accent = media.current.accent {
            ZStack {
                // Small soft bloom right at the edge.
                NotchEdgeShape(cornerRadius: radius)
                    .stroke(accent, lineWidth: 4)
                    .blur(radius: 5)
                    .opacity(isExpanded ? 0.5 : 0.35)
                // The line itself, hugging the silhouette.
                NotchEdgeShape(cornerRadius: radius)
                    .stroke(accent, lineWidth: 1.5)
                    .blur(radius: 0.5)
                    .opacity(isExpanded ? 0.95 : 0.7)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.smooth(duration: 0.8), value: media.current.accent)
        }
    }
}

/// The notch silhouette minus its top edge, for stroking. The top sits against
/// the screen edge right beside the notch cutout, where a light hairline would
/// give the cutout away.
struct NotchEdgeShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}

/// A rectangle whose bottom corners are rounded — the classic notch silhouette.
struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Collapsed strip indicators, shown only on the simulated (non-notch) strip.
private struct CollapsedContent: View {
    @ObservedObject var media: NowPlayingManager
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack {
            if media.isPlaying {
                if let art = media.current.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Image(systemName: "waveform")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            Spacer()
            if battery.isCharging {
                BatteryBolt()
            } else if battery.isPresent && battery.level < 0.2 {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .transaction { $0.animation = nil } // indicators shouldn't wiggle during expand
    }
}

/// Expanded panel: a slim header (clock, weather, battery, settings) over a
/// horizontal three-column body — media · calendar week · shelf.
private struct ExpandedContent: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 9) {
            HeaderRow(viewModel: viewModel)

            HStack(alignment: .center, spacing: 14) {
                if settings.showMedia {
                    MediaView(media: viewModel.media)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if settings.showMedia && (settings.showCalendar || settings.showShelf) {
                    columnDivider
                }
                if settings.showCalendar {
                    CalendarWeekStrip(calendar: viewModel.calendar)
                        .frame(maxWidth: .infinity)
                }
                if settings.showCalendar && settings.showShelf {
                    columnDivider
                }
                if settings.showShelf {
                    TrayView(tray: viewModel.tray)
                        .frame(maxWidth: (settings.showMedia || settings.showCalendar) ? 150 : .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    private var columnDivider: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.14), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
    }
}

/// Slim top strip: live clock on the left; weather, battery, and a settings
/// gear on the right.
private struct HeaderRow: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 9) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                if settings.showWeather {
                    WeatherPill(weather: viewModel.weather)
                }
                BatteryView(battery: viewModel.battery)
                Button { viewModel.onOpenSettings?() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }
}

/// Small capsule with the current conditions; hidden until a snapshot arrives.
private struct WeatherPill: View {
    @ObservedObject var weather: WeatherProvider

    var body: some View {
        if let snapshot = weather.current {
            HStack(spacing: 5) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                Text(snapshot.temperatureText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
            .help(snapshot.summary)
            .transition(.blurReplace)
        }
    }
}

/// Horizontal week strip — month + a 7-day window centred on today (today
/// highlighted) — with the next event (or "Nothing for today") beneath it.
private struct CalendarWeekStrip: View {
    @ObservedObject var calendar: CalendarModel

    private let accent = Color(red: 0.28, green: 0.6, blue: 1.0)

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = context.date
            let cal = Calendar.current
            let days = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }

            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(today, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .fixedSize()
                    HStack(spacing: 3) {
                        ForEach(days, id: \.self) { day in
                            let isToday = cal.isDate(day, inSameDayAs: today)
                            VStack(spacing: 3) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(isToday ? accent : .white.opacity(0.3))
                                Text(day, format: .dateTime.day())
                                    .font(.system(size: 13, weight: isToday ? .bold : .regular, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isToday ? accent : .white.opacity(0.6))
                            }
                            .frame(width: 21)
                        }
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 9.5))
                    Text(subtitle).font(.system(size: 10)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.3), value: calendar.upcoming)
        }
    }

    private var subtitle: String {
        if !calendar.isAuthorized { return "Calendar access off" }
        if let next = calendar.upcoming.first { return "\(next.timeText) · \(next.title)" }
        return "Nothing for today"
    }
}
