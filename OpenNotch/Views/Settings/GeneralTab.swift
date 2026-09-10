import SwiftUI

/// How AloeNotch starts, how you open it, and where the panel sits.
///
/// Ordered by when you meet each thing: it launches, you open it, you adjust
/// where it opens, and the tour is at the bottom because you have already had
/// it. The shortcut sits second rather than last because it is now one of the
/// two ways in, not a power-user extra.
struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotKeys = HotKeyManager.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    let onReposition: () -> Void
    let onShowWelcome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection("Startup", index: 0) {
                SettingsRow("Open at login", symbol: "power",
                            description: "AloeNotch starts with your Mac and stays out of the Dock.") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
            }

            SettingsSection("Opening the panel", index: 1) {
                SettingsRow("Keyboard shortcut", symbol: "keyboard",
                            description: "Opens and closes the panel from anywhere, and keeps it open until you press it again.") {
                    Toggle("", isOn: $settings.hotKeyEnabled).labelsHidden()
                }

                if settings.hotKeyEnabled {
                    SettingsDivider()

                    SettingsRow("Combination", symbol: "command",
                                description: settings.hotKeyCombo.caution) {
                        Picker("", selection: $settings.hotKeyCombo) {
                            ForEach(HotKeyCombo.allCases) { combo in
                                Text(combo.title).tag(combo)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    // Carbon refuses a combo another process already owns, and
                    // there is no way to find out which. Saying so beats a
                    // shortcut that silently does nothing.
                    if !hotKeys.isRegistered {
                        SettingsNote(
                            "Another app is already using \(settings.hotKeyCombo.title). Pick a different combination.",
                            tone: .warning
                        )
                    }
                }
            }
            // The combination row and its warning slide in and out rather than
            // popping, so switching the shortcut off doesn't make the card
            // below it jump up the window.
            .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                       value: settings.hotKeyEnabled)
            .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                       value: hotKeys.isRegistered)

            SettingsSection("Where it opens", index: 2) {
                SettingsSliderRow(
                    title: "Horizontal offset",
                    symbol: "arrow.left.and.right",
                    description: "Nudges the panel left or right. Leave at 0 to keep the collapsed strip aligned with the hardware notch.",
                    value: $settings.positionOffset,
                    range: -400...400,
                    valueLabel: "\(Int(settings.positionOffset)) pt",
                    accessory: AnyView(
                        Button("Center") { settings.positionOffset = 0 }
                            .controlSize(.small)
                            .glassButtonStyle(settings.useGlass)
                            .disabled(settings.positionOffset == 0)
                    )
                )

                SettingsDivider()

                SettingsSliderRow(
                    title: "Width",
                    symbol: "arrow.left.and.right.square",
                    description: "How wide the panel opens.",
                    value: $settings.panelWidth,
                    range: AppSettings.panelWidthRange,
                    step: 4,
                    valueLabel: "\(Int(settings.panelWidth)) pt"
                )

                SettingsDivider()

                SettingsRow("Display", symbol: "display",
                            description: "Move the panel to whichever screen the pointer is on.",
                            highlightsOnHover: true) {
                    Button("Move Here", action: onReposition)
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }

            SettingsSection("Onboarding", index: 3) {
                SettingsRow("Welcome screen", symbol: "sparkles",
                            description: "The first-run introduction, including the hover demo.",
                            highlightsOnHover: true) {
                    Button("Show", action: onShowWelcome)
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }
        }
    }
}
