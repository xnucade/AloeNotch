import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps the notch treats as full screen whenever they're in front.
///
/// Add and remove the way Login Items does in System Settings: an open panel
/// to pick from, and a remove button per row. No list of running apps to pick
/// from — the app you want to quiet is often not running while you're here.
struct QuietAppsList: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow("Also stay out of these apps", symbol: "app.badge",
                        description: "Whenever one of them is in front, the notch behaves as it does over a full-screen app — for a game or presentation that runs in a window.",
                        highlightsOnHover: true) {
                Button("Add App…", action: add)
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
            }

            ForEach(settings.quietApps, id: \.self) { id in
                QuietAppRow(bundleID: id) {
                    withAnimation(Motion.contentFade) {
                        settings.quietApps.removeAll { $0 == id }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.contentFade, value: settings.quietApps)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose apps for the notch to stay out of.")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        withAnimation(Motion.contentFade) {
            settings.quietApps = QuietApps.adding(ids, to: settings.quietApps,
                                                  ownID: Bundle.main.bundleIdentifier)
        }
    }
}

/// One listed app: its icon and name, indented under the row that owns the
/// list, with a remove button.
private struct QuietAppRow: View {
    let bundleID: String
    let remove: () -> Void

    @State private var hovering = false

    /// Nil when the app has since been deleted. It stays listed — by its
    /// identifier, so it can still be removed — rather than vanishing, which
    /// would make a reinstall come back quiet with no visible reason.
    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    private var name: String {
        guard let url else { return bundleID }
        // Finder's name, which drops ".app" unless the user shows extensions.
        let shown = FileManager.default.displayName(atPath: url.path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)

            Text(name)
                .font(.body)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.6)
            .help("Remove \(name)")
            .accessibilityLabel("Remove \(name)")
        }
        .padding(.leading, SettingsMetrics.controlIndent)
        .padding(.trailing, SettingsMetrics.rowInsetH)
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}
