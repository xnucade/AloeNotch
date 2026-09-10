import SwiftUI

/// Layout primitives for the preferences window.
///
/// These exist so the five panes cannot drift apart. Settings windows go wrong
/// in a very specific way — each pane is written on a different day, and the
/// spacing, label widths and description styling end up subtly different, which
/// reads as amateur even when every individual pane looks fine.
///
/// The rule here is that **every line in the window is a `SettingsRow`**. There
/// were three hand-rolled copies of the same row before this — the plain one,
/// the update row and the permission row — with different vertical alignments
/// and different gaps between the glyph and the label, which is exactly the
/// kind of thing that reads as rough without being nameable.

// MARK: - Metrics

/// The window's own spacing scale. Named so a change lands everywhere at once.
enum SettingsMetrics {
    static let rowInsetH: CGFloat = 12
    static let rowInsetV: CGFloat = 9
    /// The glyph column. Every row reserves it, glyph or not, so labels line up
    /// down the whole window rather than per-section.
    static let glyphColumn: CGFloat = 18
    static let glyphGap: CGFloat = 10
    /// Where a control sits when it is under its label rather than beside it:
    /// lined up with the label, not the card edge.
    static var controlIndent: CGFloat { rowInsetH + glyphColumn + glyphGap }
    static let cardRadius: CGFloat = 12
    static let sectionGap: CGFloat = 16
    static let contentInset: CGFloat = 18
}

// MARK: - Section

/// A titled group of rows on a single surface, mirroring System Settings.
struct SettingsSection<Content: View>: View {
    let title: String?
    /// Position in the pane, for the staggered entrance. Nil opts out.
    var index: Int?
    @ViewBuilder var content: Content

    @ObservedObject private var settings = AppSettings.shared

    init(_ title: String? = nil, index: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.index = index
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
            .panelSurface(cornerRadius: SettingsMetrics.cardRadius, glass: settings.useGlass)
        }
        .settingsEntrance(index)
    }
}

// MARK: - Row

/// One line: a glyph, a title, an optional explanation, and a control.
///
/// The control is centred against the *title*, not the whole row — so a long
/// description growing to three lines doesn't drag the switch down away from
/// the thing it is labelling.
struct SettingsRow<Control: View>: View {
    let title: String
    var symbol: String?
    /// Overrides the glyph's colour — used by rows that report a state.
    var symbolTint: Color?
    var description: String?
    /// A small status glyph beside the title, for rows that have a state to
    /// report (a permission granted, an update waiting).
    var badge: (symbol: String, tint: Color)?
    /// Whether the whole row responds to the pointer. On for rows whose control
    /// is a button or a link, where the row is really one target; off for rows
    /// with a switch, where the switch is the target and a highlight behind it
    /// would suggest the row itself does something.
    var highlightsOnHover = false
    @ViewBuilder var control: Control

    @State private var hovering = false
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    init(_ title: String,
         symbol: String? = nil,
         symbolTint: Color? = nil,
         description: String? = nil,
         badge: (symbol: String, tint: Color)? = nil,
         highlightsOnHover: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.symbol = symbol
        self.symbolTint = symbolTint
        self.description = description
        self.badge = badge
        self.highlightsOnHover = highlightsOnHover
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.glyphGap) {
            // Reserved whether or not there is a glyph, so a section that mixes
            // the two still lines its labels up.
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(symbolTint ?? .secondary)
                }
            }
            .frame(width: SettingsMetrics.glyphColumn)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13))
                    if let badge {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(badge.tint)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
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
        .padding(.horizontal, SettingsMetrics.rowInsetH)
        .padding(.vertical, SettingsMetrics.rowInsetV)
        .background {
            if highlightsOnHover {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.06 : 0))
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(.rect)
        .onHover { inside in
            guard highlightsOnHover else { return }
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: a11y.reduceMotion)) {
                hovering = inside
            }
        }
        .animation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion),
                   value: description)
    }
}

/// A row whose control is a slider under the label rather than beside it.
///
/// Sliders used to be a row followed by a loose `Slider` with its own hand-typed
/// padding, which is why they never quite lined up with anything. This makes the
/// pairing one thing.
struct SettingsSliderRow: View {
    let title: String
    var symbol: String?
    var description: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// The current value, formatted. Shown where a control would otherwise be.
    let valueLabel: String
    /// An optional button beside the readout — "Center", "Reset".
    var accessory: AnyView?
    var isDisabled = false

    private var snapped: Binding<Double> {
        Binding(get: { value },
                set: { value = (($0 / step).rounded()) * step })
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title, symbol: symbol, description: description) {
                HStack(spacing: 8) {
                    Text(valueLabel)
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    if let accessory { accessory }
                }
            }
            // Continuous, with the value snapped in the binding instead of
            // passed as `step`. AppKit draws a tick mark per step, so the
            // offset slider — 800 steps across its range — came out as a
            // dotted line under the track. Same values, no confetti.
            Slider(value: snapped, in: range)
                .controlSize(.small)
                // Same indent as a stacked picker, so every control that sits
                // under its label starts on one vertical line down the pane.
                .padding(.leading, SettingsMetrics.controlIndent)
                .padding(.trailing, SettingsMetrics.rowInsetH)
                .padding(.bottom, 10)
                .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.5 : 1)
    }
}

/// A row whose control sits *under* the label rather than beside it.
///
/// For anything wide — a segmented picker, a row of colour swatches. Beside a
/// 190pt picker the description column is barely 300pt, which turned a
/// two-line explanation into four short ragged ones. Under it, the text gets
/// the full width and the control gets a consistent home.
struct SettingsStackedRow<Control: View>: View {
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
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title, symbol: symbol, description: description) {
                EmptyView()
            }
            control
                // Indented to the label column, not the card edge: the control
                // belongs to the label above it, and starting it further left
                // than its own title reads as a separate thing.
                .padding(.leading, SettingsMetrics.controlIndent)
                .padding(.trailing, SettingsMetrics.rowInsetH)
                .padding(.bottom, 11)
        }
    }
}

/// Hairline between rows. Inset to match the label column so it reads as a
/// separator inside a group rather than a full-bleed cut across the card.
struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.35).padding(.leading, SettingsMetrics.rowInsetH)
    }
}

/// A list of switches with dividers already between them.
///
/// The Modules pane is nothing but switches, and hand-placing a divider after
/// each one is a thing you eventually forget — which had already happened
/// between two rows by the time this was written.
struct SettingsToggleList: View {
    struct Item: Identifiable {
        let title: String
        let symbol: String
        let description: String
        let binding: Binding<Bool>
        var id: String { title }
    }

    let items: [Item]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { SettingsDivider() }
                SettingsRow(item.title, symbol: item.symbol, description: item.description) {
                    Toggle("", isOn: item.binding).labelsHidden()
                }
            }
        }
    }
}

// MARK: - Note

/// An inline aside inside a section — something to know, or something to fix,
/// sitting where the thing it is about is rather than in an alert.
struct SettingsNote: View {
    enum Tone {
        case info, warning

        var tint: Color {
            switch self {
            case .info:    .secondary
            case .warning: .orange
            }
        }
        var symbol: String {
            switch self {
            case .info:    "info.circle"
            case .warning: "exclamationmark.triangle.fill"
            }
        }
    }

    let text: String
    var tone: Tone = .info

    init(_ text: String, tone: Tone = .info) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsMetrics.glyphGap) {
            Image(systemName: tone.symbol)
                .font(.system(size: 11))
                .frame(width: SettingsMetrics.glyphColumn)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tone.tint)
        .padding(.horizontal, SettingsMetrics.rowInsetH)
        .padding(.vertical, SettingsMetrics.rowInsetV)
    }
}

// MARK: - Entrance

/// Sections arrive in sequence when a pane appears.
///
/// Driven from `onAppear` rather than `.transition`, for the same reason the
/// notch's own entrance is: a parent's transition takes precedence over its
/// descendants', so staggered transitions on children inside an inserted
/// container do nothing at all.
private struct SettingsEntrance: ViewModifier {
    let index: Int?
    @State private var arrived = false
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    /// Small enough that the pane still feels immediate. A settings window that
    /// makes you wait to read it has chosen the wrong thing to optimise.
    private static let step: Double = 0.035

    func body(content: Content) -> some View {
        let on = arrived || a11y.reduceMotion || index == nil
        return content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 6)
            .onAppear {
                guard let index, !a11y.reduceMotion else { arrived = true; return }
                arrived = false
                withAnimation(Motion.arrival.delay(Double(index) * Self.step)) {
                    arrived = true
                }
            }
    }
}

extension View {
    func settingsEntrance(_ index: Int?) -> some View {
        modifier(SettingsEntrance(index: index))
    }
}
