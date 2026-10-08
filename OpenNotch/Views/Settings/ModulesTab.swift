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
    @ObservedObject private var battery = HeadphoneBattery.shared

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
                    .init(title: "Lyrics", symbol: "quote.bubble",
                          description: "The line being sung, under the track title; click it to see the next line too. Looks up the track's name on LRCLIB, a free lyrics database.",
                          binding: $settings.showLyrics),
                    .init(title: "Live equalizer", symbol: "waveform",
                          description: "Bars that follow the music instead of a loop. Asks to record system audio, which is measured and never kept; macOS may show its recording indicator while the bars are on screen.",
                          binding: $settings.liveEqualizer),
                    .init(title: "Calendar", symbol: "calendar",
                          description: "Your week, and the next event.",
                          binding: $settings.showCalendar),
                    .init(title: "Weather", symbol: "cloud.sun",
                          description: "Local conditions in the panel header.",
                          binding: $settings.showWeather),
                    .init(title: "Battery", symbol: "battery.100",
                          description: "Charge level in the panel, and a word in the notch when you plug in, at 20% and 10%, and when Low Power Mode changes.",
                          binding: $settings.showBattery),
                ])
            }

            SettingsSection("Tools", index: 1) {
                SettingsToggleList(items: [
                    .init(title: "Shelf", symbol: "tray.full",
                          description: "Drag files onto the notch to park them. Right-click one to compress it or convert an image; the result is saved beside the original.",
                          binding: $settings.showShelf),
                    .init(title: "Clipboard", symbol: "doc.on.clipboard",
                          description: "Your last 24 copies, plus up to six you pin. Search it, or ⌥-click to copy without formatting. Kept in memory only — cleared when AloeNotch quits, never written to disk, and anything a password manager marks as private is skipped.",
                          binding: $settings.showClipboard),
                    .init(title: "Timer", symbol: "timer",
                          description: "A countdown, stopwatch or focus session that takes over the collapsed notch while it runs.",
                          binding: $settings.showTimer),
                ])

                if settings.showShelf {
                    SettingsDivider()
                    SettingsRow("Empty shelf after dragging out", symbol: "tray.and.arrow.up",
                                description: "Files leave the shelf once you drop them somewhere. Off, they stay until you remove them.") {
                        Toggle("", isOn: $settings.shelfClearsAfterDrag).labelsHidden()
                    }
                }

                SettingsDivider()
                SettingsNote("These share one column, as tabs. Whichever are switched on appear there; a running timer brings its own tab forward.")
            }

            SettingsSection("Announcements", index: 2) {
                SettingsRow("Volume & Brightness", symbol: "speaker.wave.2",
                            description: "Replaces the macOS HUD with a readout in the notch, and shows the keyboard backlight level when it changes.") {
                    Toggle("", isOn: $settings.showHUD).labelsHidden()
                }

                if settings.showHUD {
                    SettingsDivider()
                    accessibilityNote

                    SettingsDivider()

                    SettingsRow("Caps Lock", symbol: "capslock",
                                description: "A brief note when it turns on or off. Uses the same Accessibility access.") {
                        Toggle("", isOn: $settings.showCapsLock).labelsHidden()
                    }
                }

                SettingsDivider()

                SettingsRow("Microphone mute", symbol: "mic.slash",
                            description: "A brief note when the microphone's mute switch flips. Reads the switch only — the microphone is never opened.") {
                    Toggle("", isOn: $settings.showMicMute).labelsHidden()
                }

                SettingsDivider()

                SettingsRow("Song changes", symbol: "music.note",
                            description: "The new song's cover and name, for a moment, when the track changes on its own or from the keyboard.") {
                    Toggle("", isOn: $settings.peekOnTrackChange).labelsHidden()
                }

                SettingsDivider()

                if settings.showCalendar {
                    SettingsRow("Next event", symbol: "calendar.badge.clock",
                                description: "Counts down to your next event in the notch for the ten minutes before it starts. All-day events are skipped.") {
                        Toggle("", isOn: $settings.showNextEventCountdown).labelsHidden()
                    }

                    SettingsDivider()
                }

                SettingsRow("Device events", symbol: "airpods.pro",
                            description: "A brief note in the notch when headphones connect or a drive mounts or ejects.") {
                    Toggle("", isOn: $settings.showDeviceEvents).labelsHidden()
                }

                if settings.showDeviceEvents {
                    SettingsDivider()

                    SettingsRow("Headphone battery", symbol: "battery.75percent",
                                description: batteryDetail) {
                        Toggle("", isOn: batteryBinding).labelsHidden()
                    }
                }
            }
            .animation(Motion.contentFade,
                       value: settings.showHUD)
            .animation(Motion.contentFade,
                       value: settings.showCalendar)
            .animation(Motion.contentFade,
                       value: settings.showDeviceEvents)
        }
    }

    /// Turning battery on is what asks for Bluetooth access — never before.
    private var batteryBinding: Binding<Bool> {
        Binding(
            get: { settings.showHeadphoneBattery && battery.authorization != .denied },
            set: { on in
                settings.showHeadphoneBattery = on
                if on { battery.requestAccess() }
            }
        )
    }

    private var batteryDetail: LocalizedStringKey {
        switch battery.authorization {
        case .denied, .restricted:
            return "Bluetooth access is off for AloeNotch. Turn it on in System Settings › Privacy & Security › Bluetooth."
        default:
            return "Show AirPods and Beats battery when they connect. Asks for Bluetooth access."
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
