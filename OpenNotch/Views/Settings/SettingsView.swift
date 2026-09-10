import SwiftUI

/// The preferences window: a floating glass tab bar over five panes.
///
/// This file is chrome only. Each pane is its own type in this folder, which is
/// the difference between five short files you can read and one 500-line file
/// where a pane written in March and a pane written in August quietly disagree
/// about spacing.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared
    let onReposition: () -> Void
    let onShowWelcome: () -> Void
    /// Which pane to open on. Defaults to General; exists so anything that
    /// tells the user to "check Settings → Access" can actually take them
    /// there instead of making them find it.
    var initialTab: Tab = .general

    /// The window's size, in one place so `AppDelegate` and the view cannot
    /// disagree about it.
    static let windowSize = CGSize(width: 560, height: 640)

    @State private var tab: Tab = .general
    /// Which way the last change moved, so the panes slide the way the tabs do.
    @State private var travellingForward = true
    @Namespace private var tabGlass

    enum Tab: String, CaseIterable, Identifiable {
        case general, modules, appearance, permissions, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:     "General"
            case .modules:     "Modules"
            case .appearance:  "Appearance"
            case .permissions: "Access"
            case .about:       "About"
            }
        }
        var symbol: String {
            switch self {
            case .general:     "gearshape"
            case .modules:     "square.grid.2x2"
            case .appearance:  "paintbrush"
            case .permissions: "lock.shield"
            case .about:       "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            tabBar
            panes
        }
        // Clears the traffic lights: the content view runs full-height under
        // the titlebar so the frost reaches the very top of the window.
        .padding(.top, 34)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear { tab = initialTab }
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }

    // MARK: Panes

    private var panes: some View {
        ScrollView {
            Group {
                switch tab {
                case .general:
                    GeneralTab(onReposition: onReposition, onShowWelcome: onShowWelcome)
                case .modules:     ModulesTab()
                case .appearance:  AppearanceTab()
                case .permissions: PermissionsTab()
                case .about:       AboutTab()
                }
            }
            .padding(.horizontal, SettingsMetrics.contentInset)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Identity per pane, so switching is a replacement rather than a
            // diff of two unrelated view trees — without it SwiftUI tries to
            // match rows across panes and animates a toggle into a slider.
            .id(tab)
            .transition(paneTransition)
        }
        .scrollContentBackground(.hidden)
        // Panes are different heights, so the scroller has to be free to size
        // itself rather than inheriting the tallest one.
        .frame(maxHeight: .infinity)
    }

    /// Panes enter from the side they live on, so the movement matches the tab
    /// you just clicked. Going right pulls the next pane in from the right.
    private var paneTransition: AnyTransition {
        guard !a11y.reduceMotion else { return .opacity }
        let enter: Edge = travellingForward ? .trailing : .leading
        let exit: Edge = travellingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: enter).combined(with: .opacity),
            removal: .move(edge: exit).combined(with: .opacity)
        )
    }

    // MARK: Tab bar

    private var tabBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    SettingsTabButton(tab: t,
                                      isActive: tab == t,
                                      glass: settings.useGlass,
                                      namespace: tabGlass) {
                        select(t)
                    }
                }
            }
            .padding(5)
            .capsuleSurface(glass: settings.useGlass)
        }
    }

    private func select(_ t: Tab) {
        guard t != tab else { return }
        let order = Tab.allCases
        travellingForward =
            (order.firstIndex(of: t) ?? 0) > (order.firstIndex(of: tab) ?? 0)
        withAnimation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion)) {
            tab = t
        }
    }
}

/// One tab. Its own type so the hover state has somewhere to live — the bar
/// previously had none at all, which left five targets that never acknowledged
/// the pointer.
private struct SettingsTabButton: View {
    let tab: SettingsView.Tab
    let isActive: Bool
    let glass: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14))
                    .frame(height: 16)
                    // The glyph acknowledges the click itself, which is what
                    // makes the bar feel like hardware rather than a segmented
                    // control that repainted.
                    .symbolEffect(.bounce, value: isActive)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            // A floor plus padding rather than a fixed width: "Appearance" is
            // wider than 76pt at this size, and forcing it into that box is
            // what made its label sit below every other one. No `maxWidth`, so
            // the bar still hugs its tabs and floats as a capsule instead of
            // stretching into a full-width segmented control.
            .padding(.horizontal, 8)
            .frame(minWidth: 76)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .background {
            if isActive {
                // Only the selected tab carries glass. Glassing every tab would
                // stack sheets and flatten the whole bar.
                Capsule()
                    .fill(.clear)
                    .capsuleSurface(glass: glass, interactive: true)
                    .glassEffectID("tab", in: namespace)
            } else if hovering {
                Capsule().fill(.primary.opacity(0.07))
            }
        }
        .onHover { inside in
            withAnimation(Motion.resolve(Motion.micro, reduceMotion: a11y.reduceMotion)) {
                hovering = inside
            }
        }
    }
}
