import SwiftUI

/// How it looks: theme, colour, material, layout, motion.
///
/// Ordered outside-in — the window's own appearance, then the colour that runs
/// through everything, then the material, then how the panel arranges itself,
/// and motion last because it is the one thing you tune after living with the
/// rest.
struct AppearanceTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    private var motion: Animation? {
        Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection("Theme", index: 0) {
                SettingsStackedRow("Windows", symbol: "circle.lefthalf.filled",
                                   description: "Applies to this window, the welcome screen and the menu bar panel. The notch itself stays black by design — that's what lets it disappear into the cutout.") {
                    Picker("", selection: $settings.windowTheme) {
                        ForEach(WindowTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            SettingsSection("Accent", index: 1) {
                SettingsStackedRow("Colour", symbol: "paintpalette",
                                   description: "Tints controls, the selected tab and today's date in the calendar. The glow around album art keeps following the artwork.") {
                    AccentPicker(hex: $settings.accentHex)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsSection("Glass", index: 2) {
                SettingsRow("Liquid Glass", symbol: "square.on.square.dashed",
                            description: "Translucent panels that pick up the desktop behind them.") {
                    Toggle("", isOn: $settings.useGlass.animation(motion)).labelsHidden()
                }
                SettingsDivider()
                SettingsStackedRow("Intensity", symbol: "slider.horizontal.below.rectangle",
                                   description: "How much frost sits between you and the desktop.") {
                    Picker("", selection: $settings.glassIntensity) {
                        ForEach(GlassIntensity.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(!settings.useGlass)
                }
                .opacity(settings.useGlass ? 1 : 0.5)

                if a11y.reduceTransparency {
                    SettingsDivider()
                    SettingsNote("Reduce Transparency is on in System Settings, so panels are solid regardless of these options.")
                }
            }
            .animation(motion, value: settings.useGlass)

            SettingsSection("Layout", index: 3) {
                SettingsStackedRow("Panel", symbol: "rectangle.split.3x1",
                                   description: settings.panelLayout.detail) {
                    // Deliberately not animated. Both layouts contain the
                    // artwork's matchedGeometryEffect, so animating the swap
                    // lets the outgoing and incoming panels exist at once with
                    // duplicate sources for the same id — undefined behaviour,
                    // and this is a rare, deliberate action that gains nothing
                    // from a transition.
                    Picker("", selection: $settings.panelLayout) {
                        ForEach(PanelLayout.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                if settings.panelLayout == .focused {
                    SettingsDivider()
                    SettingsNote("Switching layouts resets the panel width to suit it — a width chosen for three columns leaves a lot of empty space with one.")
                }
            }
            .animation(motion, value: settings.panelLayout)

            SettingsSection("Motion", index: 4) {
                SettingsRow("Ambient glow", symbol: "sparkles",
                            description: "A thin line of the artwork's colour hugging the panel edge.") {
                    Toggle("", isOn: $settings.ambientGlow).labelsHidden()
                }
                SettingsDivider()
                SettingsSliderRow(
                    title: "Animation speed",
                    symbol: "speedometer",
                    description: "Scales every transition in the app.",
                    value: $settings.animationSpeed,
                    range: 0.5...2.0,
                    step: 0.1,
                    valueLabel: String(format: "%.1f×", settings.animationSpeed),
                    isDisabled: a11y.reduceMotion
                )
                if a11y.reduceMotion {
                    SettingsNote("Reduce Motion is on in System Settings, so animations are shortened to plain fades regardless of this setting.")
                }
            }
        }
    }
}
