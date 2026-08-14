import SwiftUI

/// The menu bar dropdown: feature switches on top, app controls below.
/// Shown via MenuBarExtra with .menuBarExtraStyle(.window).
///
/// Glass here, matching the welcome and settings windows: frosted behind-window
/// backdrop so the desktop shows through, with the cards floating on top.
struct SettingsMenuView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    let onReposition: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    VStack(spacing: 6) {
                        toggleRow("sparkles", "Ambient Glow", $settings.ambientGlow)
                        toggleRow("music.note", "Now Playing", $settings.showMedia)
                        toggleRow("tray.full", "Shelf", $settings.showShelf)
                        toggleRow("calendar", "Calendar", $settings.showCalendar)
                        toggleRow("cloud.sun", "Weather", $settings.showWeather)
                        toggleRow("speaker.wave.2", "Volume & Brightness", $settings.showHUD)
                    }
                    .padding(11)
                    .panelSurface(cornerRadius: 16, glass: settings.useGlass)

                    VStack(spacing: 6) {
                        toggleRow("power", "Launch at Login", $settings.launchAtLogin)
                        Divider().opacity(0.4)
                        if let newVersion = updates.availableVersion {
                            // Only ever shown when there is something to say —
                            // a permanent "you're up to date" row would be
                            // noise in a menu this small.
                            menuButton("arrow.down.circle.fill",
                                       "Update to \(newVersion)",
                                       tint: .accentColor) {
                                updates.openReleasesPage()
                            }
                        }
                        menuButton("gearshape", "Settings…", action: onOpenSettings)
                        menuButton("arrow.up.to.line", "Reposition", action: onReposition)
                        menuButton("xmark.circle", "Quit AloeNotch",
                                   tint: .red) { NSApp.terminate(nil) }
                    }
                    .padding(11)
                    .panelSurface(cornerRadius: 16, glass: settings.useGlass)
                }
            .padding(12)
        }
        .frame(width: 268)
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .foregroundStyle(.tint)
            Text("AloeNotch")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func toggleRow(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func menuButton(_ symbol: String, _ title: String,
                            tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 18)
                Text(title).font(.system(size: 12))
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
    }
}
