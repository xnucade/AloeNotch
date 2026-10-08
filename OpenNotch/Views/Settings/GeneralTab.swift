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

    private var displayDetail: LocalizedStringKey {
        switch settings.displayChoice {
        case .automatic: "Your Mac's built-in display while it's open, the main display when the lid is closed."
        case .main:      "Always the display with the menu bar."
        case .chosen:    "The display you picked. Automatic while it isn't connected."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection("Startup", index: 0) {
                SettingsRow("Open at login", symbol: "power",
                            description: "AloeNotch starts with your Mac and stays out of the Dock.") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
            }

            SettingsSection("Opening the panel", index: 1) {
                SettingsRow("Open on", symbol: "cursorarrow.rays",
                            description: LocalizedStringKey(settings.openTrigger.detail)) {
                    Picker("", selection: $settings.openTrigger) {
                        ForEach(OpenTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                SettingsDivider()

                SettingsRow("Keyboard shortcut", symbol: "keyboard",
                            description: "Opens and closes the panel from anywhere, and keeps it open until you press it again.") {
                    Toggle("", isOn: $settings.hotKeyEnabled).labelsHidden()
                }

                if settings.hotKeyEnabled {
                    SettingsDivider()

                    SettingsRow("Combination", symbol: "command",
                                description: settings.hotKeyCombo.caution.map { LocalizedStringKey($0) }) {
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
            .animation(Motion.contentFade,
                       value: settings.hotKeyEnabled)
            .animation(Motion.contentFade,
                       value: hotKeys.isRegistered)

            SettingsSection("Where it opens", index: 2) {
                // Only where there's no notch to sit on. On a real notch the
                // strip has to hug the cutout, so an offset could only break it.
                if !NotchGeometry.metrics(for: NotchGeometry.preferredScreen()).hasHardwareNotch {
                    SettingsSliderRow(
                        title: "Horizontal offset",
                        symbol: "arrow.left.and.right",
                        description: "Moves the notch left or right on this display, which has no notch of its own.",
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
                }

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

                SettingsRow("Show on", symbol: "display.2",
                            description: displayDetail) {
                    Picker("", selection: $settings.displayChoice) {
                        Text("Automatic").tag(DisplayChoice.automatic)
                        Text("Main display").tag(DisplayChoice.main)
                        if let pinned = settings.pinnedDisplay {
                            Text(pinned).tag(DisplayChoice.chosen)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                SettingsDivider()

                SettingsRow("Display", symbol: "display",
                            description: "Keep the panel on whichever screen the pointer is on now.",
                            highlightsOnHover: true) {
                    Button("Move Here", action: onReposition)
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }

            SettingsSection("Full screen", index: 3) {
                SettingsRow("Stay out of full-screen apps", symbol: "arrow.up.left.and.arrow.down.right",
                            description: "While a game or video is full screen, the pointer won't open the notch and only volume and brightness appear. The shortcut still opens it.") {
                    Toggle("", isOn: $settings.hideInFullScreen).labelsHidden()
                }

                SettingsDivider()

                QuietAppsList(settings: settings)
            }

            SettingsSection("Screen sharing", index: 4) {
                SettingsRow("Hide from screen captures", symbol: "rectangle.dashed.badge.record",
                            description: "Keeps the notch out of screenshots, recordings and shared screens. Some capture apps ignore this on recent macOS.") {
                    Toggle("", isOn: $settings.hideFromCapture).labelsHidden()
                }

                SettingsDivider()

                SettingsRow("Hide clipboard during calls", symbol: "eye.slash",
                            description: "While your microphone is in use, clipboard rows show only what kind of thing they are.") {
                    Toggle("", isOn: $settings.blurClipboardInCalls).labelsHidden()
                }
            }

            SettingsSection("Onboarding", index: 5) {
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
