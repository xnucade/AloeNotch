import SwiftUI

/// The menu bar dropdown: feature switches on top, app controls below.
/// Shown via MenuBarExtra with .menuBarExtraStyle(.window).
struct SettingsMenuView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onReposition: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(.secondary)
                Text("AloeNotch")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            VStack(spacing: 8) {
                toggleRow("sparkles", "Ambient Glow", $settings.ambientGlow)
                toggleRow("music.note", "Now Playing", $settings.showMedia)
                toggleRow("tray.full", "Shelf", $settings.showShelf)
                toggleRow("calendar", "Calendar", $settings.showCalendar)
                toggleRow("cloud.sun", "Weather", $settings.showWeather)
            }

            Divider()

            toggleRow("power", "Launch at Login", $settings.launchAtLogin)

            Divider()

            HStack {
                Button {
                    onReposition()
                } label: {
                    Label("Reposition", systemImage: "arrow.up.to.line")
                        .font(.system(size: 11))
                }
                Spacer()
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                        .font(.system(size: 11))
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 250)
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
}
