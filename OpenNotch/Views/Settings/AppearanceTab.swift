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

    /// Intensity applies to both kinds of glass, so it's live if either is.
    private var anyGlass: Bool { settings.useGlass || settings.notchStyle == .glass }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection("Theme", index: 0) {
                SettingsStackedRow("Windows", symbol: "circle.lefthalf.filled",
                                   description: "Applies to this window, the welcome screen and the menu bar panel. The notch has its own style below.") {
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
                SettingsStackedRow("Notch", symbol: "capsule.portrait.tophalf.filled",
                                   description: settings.notchStyle.detail) {
                    Picker("", selection: $settings.notchStyle.animation(motion)) {
                        ForEach(NotchStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                SettingsDivider()
                SettingsRow("Liquid Glass", symbol: "square.on.square.dashed",
                            description: "Translucent settings, welcome and menu bar panels that pick up the desktop behind them.") {
                    Toggle("", isOn: $settings.useGlass.animation(motion)).labelsHidden()
                }
                SettingsDivider()
                SettingsStackedRow("Intensity", symbol: "slider.horizontal.below.rectangle",
                                   description: "How much frost sits between you and the desktop — here and on a glass notch.") {
                    Picker("", selection: $settings.glassIntensity) {
                        ForEach(GlassIntensity.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(!anyGlass)
                }
                .opacity(anyGlass ? 1 : 0.5)

                if a11y.reduceTransparency {
                    SettingsDivider()
                    SettingsNote("Reduce Transparency is on in System Settings, so panels are solid regardless of these options.")
                }
            }
            .animation(motion, value: settings.useGlass)
            .animation(motion, value: settings.notchStyle)

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
                SettingsRow("Personality", symbol: "wand.and.rays",
                            description: personalityDetail) {
                    Picker("", selection: personalityBinding) {
                        ForEach(MotionPersonality.allCases) { Text($0.title).tag(Optional($0)) }
                        if MotionPersonality.matching(settings.motionBounce) == nil {
                            Text("Custom").tag(Optional<MotionPersonality>.none)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .disabled(a11y.reduceMotion)
                }

                // Closing is deliberately excluded from all of this, and saying
                // so here is cheaper than fielding the bug report.
                SettingsNote("Closing never bounces — the collapsed strip has to land on the hardware notch exactly.")

                DisclosureGroup("Custom amount") {
                    SettingsSliderRow(
                        title: "Bounce",
                        symbol: "arrow.up.and.down",
                        description: nil,
                        value: $settings.motionBounce,
                        range: MotionPersonality.range,
                        step: 0.01,
                        valueLabel: String(format: "%.2f", settings.motionBounce),
                        isDisabled: a11y.reduceMotion
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                SettingsDivider()

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

            SettingsSection("Readouts", index: 5) {
                SettingsRow("Colour", symbol: "slider.horizontal.below.square.filled.and.square",
                            description: settings.hudTintMode.detail) {
                    Picker("", selection: $settings.hudTintMode) {
                        ForEach(HUDTintMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                }

                if settings.hudTintMode == .perKind {
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Volume")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        AccentPicker(hex: $settings.hudVolumeHex)
                        Text("Brightness")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        AccentPicker(hex: $settings.hudBrightnessHex)
                    }
                    .padding(12)
                }

                if settings.hudTintMode == .artwork {
                    SettingsNote("Nothing playing means no artwork colour, so the readouts stay white until something is.")
                }
            }
        }
    }

    /// The description under the personality picker: the chosen preset's own
    /// line, or the raw number when the user has dialled something between two.
    private var personalityDetail: String {
        MotionPersonality.matching(settings.motionBounce)?.detail
            ?? String(format: "A custom amount of overshoot (%.2f).", settings.motionBounce)
    }

    /// The segmented control writes a preset's scalar; a custom value shows as
    /// no selection rather than silently snapping to the nearest preset.
    private var personalityBinding: Binding<MotionPersonality?> {
        Binding(
            get: { MotionPersonality.matching(settings.motionBounce) },
            set: { if let p = $0 { settings.motionBounce = p.bounce } }
        )
    }
}
