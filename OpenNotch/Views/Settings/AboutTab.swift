import SwiftUI

/// What this is, whether it is current, and where to go from here.
struct AboutTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
            SettingsSection(index: 0) {
                identity
                SettingsDivider()
                Text("A Dynamic Island for your MacBook. Free and open source.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.rowInsetH)
                    .padding(.vertical, 12)
            }

            SettingsSection("Updates", index: 1) {
                UpdateRow()
                SettingsDivider()
                SettingsRow("Check automatically", symbol: "clock.arrow.circlepath",
                            description: "Asks GitHub once a day whether a newer release exists. Sends nothing but a version number.") {
                    Toggle("", isOn: $settings.checkForUpdates).labelsHidden()
                }
            }

            SettingsSection("Links", index: 2) {
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

            SettingsSection(index: 3) {
                SettingsRow("Quit AloeNotch", symbol: "power",
                            description: "The notch disappears until you launch it again.",
                            highlightsOnHover: true) {
                    Button("Quit") { NSApp.terminate(nil) }
                        .controlSize(.small)
                        .glassButtonStyle(settings.useGlass)
                }
            }
        }
    }

    private var identity: some View {
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
        .padding(.horizontal, SettingsMetrics.rowInsetH)
        .padding(.vertical, 12)
    }

    /// The whole row opens the link, not just the little arrow — a 12pt glyph
    /// is a needlessly small target for something whose entire job is "go here".
    private func linkRow(_ title: String, _ symbol: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            SettingsRow(title, symbol: symbol, highlightsOnHover: true) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
