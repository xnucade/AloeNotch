import SwiftUI

/// Rows with a job of their own — an accent picker, the update check, one
/// system permission.
///
/// All three used to hand-roll the same `HStack` the plain row already draws,
/// with different vertical alignments and different gaps, so labels down the
/// window didn't line up. They compose `SettingsRow` now; the only thing they
/// own is what goes in the control slot.

// MARK: - Accent

/// A row of curated swatches plus a custom well.
///
/// Selection is shown with a ring *around* the swatch rather than a checkmark
/// on top of it: a mark drawn over the colour has to be either light or dark,
/// and whichever is chosen disappears against some of the swatches.
struct AccentPicker: View {
    @Binding var hex: String
    @Environment(\.notchReduceMotion) private var reduceMotion

    /// The custom well's own colour, seeded from the current selection so
    /// opening the picker starts where the user already is.
    @State private var customColor: Color = .accentColor

    private var isCustom: Bool {
        !AccentPalette.swatches.contains { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentPalette.swatches) { swatch in
                swatchButton(swatch)
            }

            // Custom. `supportsOpacity: false` because a translucent accent
            // would read as washed-out chrome rather than a colour choice.
            ColorPicker("Custom colour", selection: $customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(isCustom ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                }
                .onChange(of: customColor) { _, new in
                    hex = new.hexString
                }
        }
        .onAppear {
            customColor = Color(hex: hex) ?? .accentColor
        }
    }

    private func swatchButton(_ swatch: AccentPalette.Swatch) -> some View {
        let selected = swatch.hex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            hex = swatch.hex
        } label: {
            Circle()
                .fill(swatch.color)
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(selected ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .help(swatch.name)
        .animation(Motion.resolve(Motion.micro, reduceMotion: reduceMotion), value: selected)
    }
}

// MARK: - Update row

/// Current version, whether a newer one exists, and a way to go get it.
///
/// Reports the *result* rather than the mechanism — "up to date" and "0.9.0 is
/// available" are the only two outcomes anyone cares about. Failures are
/// deliberately understated: being offline is the usual reason, and it is not
/// an error the user needs to act on.
struct UpdateRow: View {
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    var body: some View {
        SettingsRow(title, symbol: symbol, symbolTint: tint, description: detail) {
            if case .available = updates.state {
                Button("Get It…") { updates.openReleasesPage() }
                    .controlSize(.small)
                    .glassProminentButtonStyle(settings.useGlass)
            } else {
                Button("Check Now") { updates.checkNow() }
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
                    .disabled(updates.state == .checking)
            }
        }
        // The glyph swaps between four states as a check runs, and a cut
        // between them makes a two-second network call look like a glitch.
        .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                   value: updates.state)
    }

    private var symbol: String {
        switch updates.state {
        case .available: "arrow.down.circle.fill"
        case .upToDate:  "checkmark.circle.fill"
        case .checking:  "arrow.triangle.2.circlepath"
        default:         "arrow.down.circle"
        }
    }

    private var tint: Color {
        switch updates.state {
        case .available: .accentColor
        case .upToDate:  .green
        default:         .secondary
        }
    }

    private var title: String {
        if case .available(let v, _) = updates.state { return "Version \(v) is available" }
        return "AloeNotch \(updates.currentVersion)"
    }

    private var detail: String {
        switch updates.state {
        case .available:
            "Opens the release page, where you can download the new version."
        case .upToDate:
            "You're on the latest release."
        case .checking:
            "Checking…"
        case .failed(let why) where !why.isEmpty:
            why
        default:
            "Last checked \(lastChecked)."
        }
    }

    private var lastChecked: String {
        let d = settings.lastUpdateCheck
        guard d > .distantPast else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Permission row

/// Status of one system permission, with a one-tap way to resolve it.
struct PermissionRow: View {
    enum Status {
        case granted
        case notDetermined
        case denied

        var symbol: String {
            switch self {
            case .granted:       "checkmark.circle.fill"
            case .notDetermined: "circle.dashed"
            case .denied:        "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .granted:       .green
            case .notDetermined: .secondary
            case .denied:        .orange
            }
        }
    }

    let title: String
    let symbol: String
    /// Why this is needed, in plain language. Shown always, not just on denial:
    /// the moment to explain a permission is before it is asked for.
    let rationale: String
    let status: Status
    /// Nil once granted — there is nothing left to do.
    var action: (() -> Void)?
    var actionTitle: String = "Grant…"

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    var body: some View {
        SettingsRow(title,
                    symbol: symbol,
                    description: rationale,
                    badge: (status.symbol, status.tint)) {
            if status != .granted, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
            }
        }
        // Granting a permission is the one moment in this window where
        // something changes because of an answer given somewhere else. The tick
        // arriving on its own, with a beat, is what confirms it landed.
        .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                   value: status)
    }
}

extension PermissionRow.Status: Equatable {}
