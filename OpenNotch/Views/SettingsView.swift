import SwiftUI
import CoreLocation

/// The full preferences window (opened from the menu bar or the panel's gear).
///
/// Five tabs behind a floating glass capsule, over a frosted behind-window
/// backdrop so the desktop shows through. Layout comes from the primitives in
/// SettingsControls.swift rather than being hand-rolled per tab, so the panes
/// cannot drift apart as they are edited.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared
    let onReposition: () -> Void
    let onShowWelcome: () -> Void

    @State private var tab: Tab = .general
    @Namespace private var tabGlass

    enum Tab: String, CaseIterable, Identifiable {
        case general, modules, appearance, permissions, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:     "General"
            case .modules:     "Modules"
            case .appearance:  "Appearance"
            case .permissions: "Access"
            case .about:       "About"
            }
        }
        var symbol: String {
            switch self {
            case .general:     "gearshape"
            case .modules:     "square.grid.2x2"
            case .appearance:  "paintbrush"
            case .permissions: "lock.shield"
            case .about:       "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            tabBar
            ScrollView {
                Group {
                    switch tab {
                    case .general:     generalTab
                    case .modules:     modulesTab
                    case .appearance:  appearanceTab
                    case .permissions: permissionsTab
                    case .about:       aboutTab
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        // Clears the traffic lights: the content view runs full-height under
        // the titlebar so the frost reaches the very top of the window.
        .padding(.top, 34)
        .frame(width: 520, height: 620)
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }

    // MARK: Tab bar

    private var tabBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    Button {
                        withAnimation(Motion.resolve(Motion.contentFade,
                                                     reduceMotion: a11y.reduceMotion)) {
                            tab = t
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.system(size: 14))
                            Text(t.title).font(.system(size: 10, weight: .medium))
                        }
                        .frame(width: 76, height: 44)
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

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Startup") {
                SettingsRow("Open at login", symbol: "power") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
            }

            SettingsSection("Panel") {
                SettingsRow("Horizontal offset",
                            symbol: "arrow.left.and.right",
                            description: "Nudges the panel left or right. Leave at 0 to keep the collapsed strip aligned with the hardware notch.") {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.positionOffset)) pt")
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Center") { settings.positionOffset = 0 }
                            .controlSize(.small)
                            .glassButtonStyle(settings.useGlass)
                            .disabled(settings.positionOffset == 0)
                    }
                }
                Slider(value: $settings.positionOffset, in: -400...400, step: 1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                SettingsDivider()

                SettingsRow("Width", symbol: "arrow.left.and.right.square",
                            description: "How wide the panel opens.") {
                    Text("\(Int(settings.panelWidth)) pt")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.panelWidth,
                       in: AppSettings.panelWidthRange, step: 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                SettingsDivider()

                SettingsRow("Display", symbol: "display",
                            description: "Move the panel to whichever screen the pointer is on.") {
                    Button("Move Here", action: onReposition)
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }

            SettingsSection("Onboarding") {
                SettingsRow("Welcome screen", symbol: "sparkles",
                            description: "The first-run introduction, including the hover demo.") {
                    Button("Show", action: onShowWelcome)
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }
        }
    }

    // MARK: Modules

    private var modulesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("In the panel") {
                moduleToggle("Now Playing", "music.note",
                             "Controls for whatever your Mac is playing.",
                             $settings.showMedia)
                SettingsDivider()
                moduleToggle("Shelf", "tray.full",
                             "Drag files onto the notch to park them.",
                             $settings.showShelf)
                SettingsDivider()
                moduleToggle("Calendar", "calendar",
                             "Your week, and the next event.",
                             $settings.showCalendar)
                SettingsDivider()
                moduleToggle("Weather", "cloud.sun",
                             "Local conditions in the panel header.",
                             $settings.showWeather)
                SettingsDivider()
                moduleToggle("Battery", "battery.100",
                             "Charge level, plus charging and low hints on the collapsed strip.",
                             $settings.showBattery)
            }

            SettingsSection("System") {
                moduleToggle("Volume & Brightness", "speaker.wave.2",
                             "Replaces the macOS HUD with a readout in the notch.",
                             $settings.showHUD)
                if settings.showHUD {
                    SettingsDivider()
                    accessibilityNote
                }
            }
        }
    }

    private func moduleToggle(_ title: String, _ symbol: String,
                              _ description: String,
                              _ binding: Binding<Bool>) -> some View {
        SettingsRow(title, symbol: symbol, description: description) {
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    /// Replacing the macOS HUD means swallowing the volume/brightness keys,
    /// which needs Accessibility. Until it's granted we leave the system HUD be.
    @State private var trusted = MediaKeyInterceptor.isTrusted

    private var accessibilityNote: some View {
        PermissionRow(
            title: "Accessibility",
            symbol: "hand.raised",
            rationale: trusted
                ? "Granted — the macOS HUD is replaced."
                : "Needed to catch the volume keys first. Without it macOS keeps drawing its own HUD, so AloeNotch stays out of the way.",
            status: trusted ? .granted : .notDetermined,
            action: trusted ? nil : { MediaKeyInterceptor.requestTrust() }
        )
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = MediaKeyInterceptor.isTrusted
        }
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Theme") {
                SettingsRow("Windows", symbol: "circle.lefthalf.filled",
                            description: "Applies to this window, the welcome screen and the menu bar panel. The notch itself stays black by design — that's what lets it disappear into the cutout.") {
                    Picker("", selection: $settings.windowTheme) {
                        ForEach(WindowTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }

            SettingsSection("Accent") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tints controls, the selected tab and today's date in the calendar. The glow around album art keeps following the artwork.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AccentPicker(hex: $settings.accentHex)
                }
                .padding(12)
            }

            SettingsSection("Glass") {
                SettingsRow("Liquid Glass", symbol: "square.on.square.dashed",
                            description: "Translucent panels that pick up the desktop behind them.") {
                    Toggle("", isOn: $settings.useGlass.animation(
                        Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion)))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Intensity", symbol: "slider.horizontal.below.rectangle",
                            description: "How much frost sits between you and the desktop.") {
                    Picker("", selection: $settings.glassIntensity) {
                        ForEach(GlassIntensity.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .disabled(!settings.useGlass)
                }
                if a11y.reduceTransparency {
                    SettingsDivider()
                    noteRow("Reduce Transparency is on in System Settings, so panels are solid regardless of these options.")
                }
            }

            SettingsSection("Motion") {
                SettingsRow("Ambient glow", symbol: "sparkles",
                            description: "A thin line of the artwork's colour hugging the panel edge.") {
                    Toggle("", isOn: $settings.ambientGlow).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Animation speed", symbol: "speedometer",
                            description: "Scales every transition in the app.") {
                    Text(speedLabel)
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .disabled(a11y.reduceMotion)
                if a11y.reduceMotion {
                    noteRow("Reduce Motion is on in System Settings, so animations are shortened to plain fades regardless of this setting.")
                }
            }
        }
    }

    private var speedLabel: String {
        String(format: "%.1f×", settings.animationSpeed)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Permissions

    private var permissionsTab: some View {
        PermissionsTab()
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
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
                .padding(12)

                SettingsDivider()

                Text("A Dynamic Island for your MacBook. Free and open source.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            SettingsSection("Links") {
                linkRow("Website", "globe", "https://aloenotch.com")
                SettingsDivider()
                linkRow("What's new", "sparkles", "https://aloenotch.com/changelog")
                SettingsDivider()
                linkRow("Source on GitHub", "chevron.left.forwardslash.chevron.right",
                        "https://github.com/xnucade/AloeNotch")
                SettingsDivider()
                linkRow("Report an issue", "exclamationmark.bubble",
                        "https://github.com/xnucade/AloeNotch/issues/new")
            }

            SettingsSection {
                SettingsRow("Quit AloeNotch", symbol: "power",
                            description: "The notch disappears until you launch it again.") {
                    Button("Quit") { NSApp.terminate(nil) }
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }
        }
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: String) -> some View {
        SettingsRow(title, symbol: symbol) {
            Link(destination: URL(string: url)!) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
