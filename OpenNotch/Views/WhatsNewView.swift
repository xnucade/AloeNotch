import SwiftUI

/// Release notes shown once, the first time a new version runs.
///
/// The notes live here rather than being fetched, so the sheet works offline
/// and can never disagree with the binary it shipped in. Keeping them beside
/// the code also means updating them is part of the same change that adds the
/// feature, instead of something to remember at release time.
enum WhatsNew {
    struct Entry {
        let version: String
        let headline: String
        let items: [Item]
    }

    struct Item: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    /// Newest first. Only the entry matching the running version is shown.
    static let entries: [Entry] = [
        Entry(
            version: "0.8.2",
            headline: "Permissions that stay put",
            items: [
                Item(symbol: "lock.rotation",
                     title: "You'll grant permissions one last time",
                     detail: "Every earlier release was signed in a way that made macOS treat each update as a different app, so Calendar, Location and Accessibility were forgotten every time you updated. Grant them once after this update and they'll stick from now on."),
                Item(symbol: "music.note",
                     title: "Now Playing works again",
                     detail: "AloeNotch was testing its media helper with a command that could never succeed, so it disabled itself even when everything was fine."),
                Item(symbol: "checkmark.shield",
                     title: "The Grant buttons actually grant",
                     detail: "Calendar and Location were missing two entitlements needed to request them, and macOS refuses those requests silently — no prompt, no error."),
                Item(symbol: "bolt.fill",
                     title: "Plugging in says so",
                     detail: "Connecting the charger briefly shows a bolt and your charge level in the notch."),
            ]
        ),
        Entry(
            version: "0.8.0",
            headline: "Smoother, and yours to tune",
            items: [
                Item(symbol: "sparkles",
                     title: "The panel moves as one piece",
                     detail: "Album art now travels out of the notch and grows into the panel, instead of the small and large versions swapping over."),
                Item(symbol: "bolt.fill",
                     title: "No more stutter on track changes",
                     detail: "Cover art is decoded off the main thread, so skipping a track no longer costs a frame just as the artwork is crossfading."),
                Item(symbol: "slider.horizontal.3",
                     title: "A real settings window",
                     detail: "Five tabs, with accent colour, panel width, glass intensity and animation speed — plus every module toggled individually."),
                Item(symbol: "hand.tap",
                     title: "It responds to you",
                     detail: "Hover and press feedback throughout, the shelf opens to catch a dragged file, and the trackpad taps on drop and on volume steps."),
                Item(symbol: "figure.walk.motion",
                     title: "Respects Reduce Motion",
                     detail: "Reduce Motion and Reduce Transparency are both honoured now, live, without a relaunch."),
            ]
        ),
    ]

    /// The newest entry at or below the running version.
    ///
    /// Not an exact match on purpose. A patch release usually has nothing worth
    /// a full-screen sheet, so it gets no entry of its own — but with exact
    /// matching, someone upgrading 0.7.0 → 0.8.1 would skip the 0.8.0 notes
    /// entirely and never learn what changed. Falling back to the most recent
    /// entry they haven't seen keeps that from happening.
    static var current: Entry? {
        guard let running = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        return entries.first { SemanticVersion.isAtOrBelow($0.version, running) }
    }

    /// Whether to show the sheet on this launch.
    ///
    /// Suppressed on a genuine first run: someone seeing the app for the first
    /// time gets the onboarding flow, and stacking "what's new" on top of
    /// "welcome" is noise. Also suppressed when there are no notes for this
    /// version, so a release with nothing user-facing stays quiet.
    static func shouldPresent(lastSeen: String, hasSeenWelcome: Bool) -> Bool {
        guard hasSeenWelcome else { return false }
        guard !lastSeen.isEmpty else { return false }
        guard let current else { return false }
        return lastSeen != current.version
    }
}

struct WhatsNewView: View {
    @ObservedObject private var settings = AppSettings.shared
    let entry: WhatsNew.Entry
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("What's new in AloeNotch")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.7)
                        Text(entry.headline)
                            .font(.system(size: 22, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text("Version \(entry.version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 34)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(entry.items) { item in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.tint)
                                    .frame(width: 24, height: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(item.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelSurface(cornerRadius: 14, glass: settings.useGlass)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: 0) {
                Divider().opacity(0.35)
                HStack {
                    Link("Full changelog",
                         destination: URL(string: "https://aloenotch.com/changelog")!)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Continue", action: onDismiss)
                        .glassProminentButtonStyle(settings.useGlass)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 470, height: 540)
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }
}
