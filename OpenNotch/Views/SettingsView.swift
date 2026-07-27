import SwiftUI

/// The full preferences window (opened from the menu bar).
///
/// Split into tabs rather than one long scroll: the settings fall into four
/// clean groups, and a single Form meant Position and General were below the
/// fold on first open. The tab bar is a floating glass capsule over a frosted,
/// behind-window backdrop, so the desktop shows through.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onReposition: () -> Void
    let onShowWelcome: () -> Void

    @State private var tab: Tab = .features
    @Namespace private var tabGlass

    enum Tab: String, CaseIterable, Identifiable {
        case features, position, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .features: "Features"
            case .position: "Position"
            case .general:  "General"
            case .about:    "About"
            }
        }
        var symbol: String {
            switch self {
            case .features: "slider.horizontal.3"
            case .position: "arrow.left.and.right"
            case .general:  "gearshape"
            case .about:    "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
                tabBar
                ScrollView {
                    Group {
                        switch tab {
                        case .features: featuresTab
                        case .position: positionTab
                        case .general:  generalTab
                        case .about:    aboutTab
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelSurface(cornerRadius: 22, glass: settings.useGlass)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            .scrollContentBackground(.hidden)
        }
        // Clears the traffic lights: the content view runs full-height under
        // the titlebar so the frost reaches the very top of the window.
        .padding(.top, 34)
        .frame(width: 460, height: 580)
        .frostedWindowBackground(settings.useGlass)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { tab = t }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.system(size: 14))
                            Text(t.title).font(.system(size: 10, weight: .medium))
                        }
                        .frame(width: 74, height: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == t ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    // Only the selected tab carries glass. Glassing every tab
                    // would stack sheets and flatten the whole bar.
                    .background {
                        if tab == t {
                            Capsule()
                                .fill(.clear)
                                .capsuleSurface(glass: settings.useGlass, interactive: true)
                                .glassEffectID("tab", in: tabGlass)
                        }
                    }
                }
            }
            .padding(5)
            .capsuleSurface(glass: settings.useGlass)
        }
    }

    // MARK: Tabs

    private var featuresTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Ambient Glow", isOn: $settings.ambientGlow)
            Toggle("Now Playing", isOn: $settings.showMedia)
            Toggle("Shelf", isOn: $settings.showShelf)
            Toggle("Calendar", isOn: $settings.showCalendar)
            Toggle("Weather", isOn: $settings.showWeather)
            Toggle("Volume & Brightness HUD", isOn: $settings.showHUD)
            if settings.showHUD {
                Divider().padding(.vertical, 2)
                accessibilityRow
            }
        }
        .toggleStyle(.switch)
    }

    private var positionTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Horizontal offset")
                Spacer()
                Text("\(Int(settings.positionOffset)) pt")
                    .foregroundStyle(.secondary).monospacedDigit()
                Button("Center") { settings.positionOffset = 0 }
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
                    .disabled(settings.positionOffset == 0)
            }
            Slider(value: $settings.positionOffset, in: -400...400, step: 1)
            Text("Nudges the panel left or right. Leave at 0 to keep the collapsed strip aligned with the hardware notch.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            Button("Move to Active Display", action: onReposition)
                .glassButtonStyle(settings.useGlass)
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
            Toggle("Use Liquid Glass", isOn: $settings.useGlass.animation(.smooth(duration: 0.35)))
                .toggleStyle(.switch)
            Text("Translucent panels that pick up what's behind them. Turn it off for solid panels if you'd rather have the contrast.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("Show Welcome Screen…", action: onShowWelcome)
                .glassButtonStyle(settings.useGlass)
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AloeNotch").font(.system(size: 15, weight: .semibold))
                    Text("Version \(version)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("A Dynamic Island for your MacBook. Free and open source.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 14) {
                Link("Website", destination: URL(string: "https://aloenotch.com")!)
                Link("Source on GitHub", destination: URL(string: "https://github.com/xnucade/AloeNotch")!)
                Spacer()
            }
            .font(.callout)

            Divider()

            Button("Quit AloeNotch") { NSApp.terminate(nil) }
                .glassButtonStyle(settings.useGlass)
        }
    }

    // MARK: Bits

    /// Replacing the macOS HUD means swallowing the volume/brightness keys,
    /// which needs Accessibility. Until it's granted we leave the system HUD be.
    @State private var trusted = MediaKeyInterceptor.isTrusted

    private var accessibilityRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(trusted ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(trusted
                     ? "Accessibility granted — the macOS HUD is replaced."
                     : "Needs Accessibility access to replace the macOS HUD.")
                    .font(.callout)
                if !trusted {
                    Text("Without it, macOS keeps drawing its own HUD, so AloeNotch stays out of the way.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if !trusted {
                Button("Grant…") { MediaKeyInterceptor.requestTrust() }
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
            }
        }
        // Pick up the grant without needing a relaunch.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = MediaKeyInterceptor.isTrusted
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
