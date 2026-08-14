import SwiftUI

/// Layout primitives for the preferences window.
///
/// These exist so the five tabs cannot drift apart. Settings panes go wrong in
/// a very specific way — each pane is written on a different day, and the
/// spacing, label widths and description styling end up subtly different, which
/// reads as amateur even when every individual pane looks fine. One set of
/// primitives makes consistency the default rather than something to remember.

// MARK: - Section

/// A titled group of rows on a single surface, mirroring the grouped boxes in
/// System Settings.
struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    @ObservedObject private var settings = AppSettings.shared

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .panelSurface(cornerRadius: 12, glass: settings.useGlass)
        }
    }
}

/// One line in a section: a label, an optional explanation, and a control.
///
/// The control is trailing and vertically centred against the *label*, not the
/// whole row — so a long description growing to three lines doesn't drag the
/// switch down away from the thing it's labelled by.
struct SettingsRow<Control: View>: View {
    let title: String
    var symbol: String?
    var description: String?
    @ViewBuilder var control: Control

    init(_ title: String,
         symbol: String? = nil,
         description: String? = nil,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.symbol = symbol
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// Hairline between rows. Inset to match the label column so it reads as a
/// separator inside a group rather than a full-bleed cut across the card.
struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.35).padding(.leading, 12)
    }
}

// MARK: - Accent picker

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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13))
                    Image(systemName: status.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(status.tint)
                }
                Text(rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if status != .granted, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .glassButtonStyle(settings.useGlass)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

extension PermissionRow.Status: Equatable {}
