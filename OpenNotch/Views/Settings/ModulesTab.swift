import SwiftUI

/// What the panel shows, in three groups.
///
/// This was one undifferentiated list of eight switches, which is the point at
/// which a settings pane stops being scannable — nothing tells you that Weather
/// and Clipboard are different kinds of thing. They are grouped by *where the
/// thing appears* instead: in the open panel, in the tools column, or on the
/// collapsed strip when something happens.
struct ModulesTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    /// Replacing the macOS HUD means swallowing the volume/brightness keys,
    /// which needs Accessibility. Until it's granted we leave the system HUD be.
    @State private var trusted = MediaKeyInterceptor.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection("In the panel", index: 0) {
                SettingsToggleList(items: [
                    .init(title: "Now Playing", symbol: "music.note",
                          description: "Controls for whatever your Mac is playing.",
                          binding: $settings.showMedia),
                    .init(title: "Calendar", symbol: "calendar",
                          description: "Your week, and the next event.",
                          binding: $settings.showCalendar),
                    .init(title: "Weather", symbol: "cloud.sun",
                          description: "Local conditions in the panel header.",
                          binding: $settings.showWeather),
                    .init(title: "Battery", symbol: "battery.100",
                          description: "Charge level, plus charging and low hints on the collapsed strip.",
                          binding: $settings.showBattery),
                ])
            }

            SettingsSection("Tools", index: 1) {
                SettingsToggleList(items: [
                    .init(title: "Shelf", symbol: "tray.full",
                          description: "Drag files onto the notch to park them.",
                          binding: $settings.showShelf),
                    .init(title: "Clipboard", symbol: "doc.on.clipboard",
                          description: "Your last 24 copies. Kept in memory only — cleared when AloeNotch quits, never written to disk, and anything a password manager marks as private is skipped.",
                          binding: $settings.showClipboard),
                    .init(title: "Timer", symbol: "timer",
                          description: "A countdown that takes over the collapsed notch while it runs.",
                          binding: $settings.showTimer),
                ])

                SettingsDivider()
                SettingsNote("These share one column, as tabs. Whichever are switched on appear there; a running timer brings its own tab forward.")
            }

            SettingsSection("Announcements", index: 2) {
                SettingsRow("Volume & Brightness", symbol: "speaker.wave.2",
                            description: "Replaces the macOS HUD with a readout in the notch.") {
                    Toggle("", isOn: $settings.showHUD).labelsHidden()
                }

                if settings.showHUD {
                    SettingsDivider()
                    accessibilityNote
                }

                SettingsDivider()

                SettingsRow("Device events", symbol: "airpods.pro",
                            description: "A brief note in the notch when headphones connect or a drive mounts or ejects.") {
                    Toggle("", isOn: $settings.showDeviceEvents).labelsHidden()
                }
            }
            .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                       value: settings.showHUD)
        }
    }

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
}
