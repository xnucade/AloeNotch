import SwiftUI
import AppKit

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

    @StateObject private var panel = ColorPanelBridge()

    private var isCustom: Bool {
        !AccentPalette.swatches.contains { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentPalette.swatches) { swatch in
                swatchButton(swatch)
            }
            customWell
        }
        .onDisappear { panel.release() }
    }

    /// Custom. Not SwiftUI's ColorPicker: on macOS 26 it draws as a wide
    /// capsule that ignores its frame and spills over the swatch beside it.
    /// This is a swatch like the others that opens the system colour panel,
    /// starting from the current accent so it begins where the user already
    /// is. A rainbow until a custom colour is chosen, then that colour.
    private var customWell: some View {
        Button {
            panel.open(with: NSColor(Color(hex: hex) ?? .accentColor)) { picked in
                hex = Color(nsColor: picked).hexString
            }
        } label: {
            Circle()
                .fill(isCustom
                      ? AnyShapeStyle(Color(hex: hex) ?? .accentColor)
                      : AnyShapeStyle(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center)))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(isCustom ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .help("Custom color")
        .accessibilityLabel("Custom color")
        .animation(Motion.micro, value: isCustom)
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
        .animation(Motion.micro, value: selected)
    }
}

/// Points the shared system colour panel at the custom well. No alpha: a
/// translucent accent reads as washed-out chrome rather than a colour choice.
private final class ColorPanelBridge: NSObject, ObservableObject {
    private var onChange: ((NSColor) -> Void)?

    func open(with color: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        // Colour first, target second, so seeding the panel doesn't report
        // itself back as a choice.
        panel.setTarget(nil)
        panel.color = color
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }

    /// Stop listening when Settings closes, so the panel left open can't
    /// keep changing the accent with nothing on screen to show it.
    func release() {
        guard onChange != nil else { return }
        NSColorPanel.shared.setTarget(nil)
        onChange = nil
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onChange?(sender.color.usingColorSpace(.sRGB) ?? sender.color)
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
                Button("Get It…") { updates.installUpdate() }
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
        .animation(Motion.contentFade,
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

    private var title: LocalizedStringKey {
        if case .available(let v) = updates.state { return "Version \(v) is available" }
        return "AloeNotch \(updates.currentVersion)"
    }

    private var detail: LocalizedStringKey {
        switch updates.state {
        case .available:
            "Shows what's new, then installs it and reopens AloeNotch."
        case .upToDate:
            "You're on the latest release."
        case .checking:
            "Checking…"
        case .failed(let why) where !why.isEmpty:
            LocalizedStringKey(why)
        default:
            "Last checked \(lastChecked)."
        }
    }

    private var lastChecked: String {
        let d = settings.lastUpdateCheck
        guard d > .distantPast else { return String(localized: "never") }
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

    let title: LocalizedStringKey
    let symbol: String
    /// Why this is needed, in plain language. Shown always, not just on denial:
    /// the moment to explain a permission is before it is asked for.
    let rationale: LocalizedStringKey
    let status: Status
    /// Nil once granted — there is nothing left to do.
    var action: (() -> Void)?
    var actionTitle: LocalizedStringKey = "Grant…"

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
        .animation(Motion.contentFade,
                   value: status)
    }
}

extension PermissionRow.Status: Equatable {}
