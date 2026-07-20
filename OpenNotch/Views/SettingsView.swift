import SwiftUI

/// The full preferences window (opened from the menu bar). The menu bar
/// dropdown keeps the quick toggles; this is the roomier home for everything,
/// including the position offset that has no place in a small menu.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onReposition: () -> Void
    let onShowWelcome: () -> Void

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

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AloeNotch").font(.system(size: 15, weight: .semibold))
                        Text("Version \(version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Features") {
                Toggle("Ambient Glow", isOn: $settings.ambientGlow)
                Toggle("Now Playing", isOn: $settings.showMedia)
                Toggle("Shelf", isOn: $settings.showShelf)
                Toggle("Calendar", isOn: $settings.showCalendar)
                Toggle("Weather", isOn: $settings.showWeather)
                Toggle("Volume & Brightness HUD", isOn: $settings.showHUD)
                if settings.showHUD { accessibilityRow }
            }

            Section("Position") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Horizontal offset")
                        Spacer()
                        Text("\(Int(settings.positionOffset)) pt")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Button("Center") { settings.positionOffset = 0 }
                            .controlSize(.small)
                            .disabled(settings.positionOffset == 0)
                    }
                    Slider(value: $settings.positionOffset, in: -400...400, step: 1)
                    Text("Nudges the panel left or right. Leave at 0 to keep the collapsed strip aligned with the hardware notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Move to Active Display", action: onReposition)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Button("Show Welcome Screen…", action: onShowWelcome)
            }

            Section {
                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://aloenotch-site.xnucade.workers.dev")!)
                    Link("Source on GitHub", destination: URL(string: "https://github.com/xnucade/AloeNotch")!)
                    Spacer()
                    Button("Quit AloeNotch") { NSApp.terminate(nil) }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 560)
    }
}
