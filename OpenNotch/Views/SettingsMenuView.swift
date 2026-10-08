import SwiftUI

/// The menu bar dropdown: feature switches on top, app controls below.
/// Shown via MenuBarExtra with .menuBarExtraStyle(.window).
///
/// Glass here, matching the welcome and settings windows: frosted behind-window
/// backdrop so the desktop shows through, with the cards floating on top.
struct SettingsMenuView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var debug = DebugTools.shared
    @StateObject private var option = OptionKeyWatcher()
    let onReposition: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    VStack(spacing: 6) {
                        toggleRow("sparkles", "Ambient Glow", $settings.ambientGlow)
                        toggleRow("music.note", "Now Playing", $settings.showMedia)
                        toggleRow("tray.full", "Shelf", $settings.showShelf)
                        toggleRow("calendar", "Calendar", $settings.showCalendar)
                        toggleRow("cloud.sun", "Weather", $settings.showWeather)
                        toggleRow("speaker.wave.2", "Volume & Brightness", $settings.showHUD)
                    }
                    .padding(11)
                    .panelSurface(cornerRadius: 16, glass: settings.useGlass)

                    VStack(spacing: 6) {
                        toggleRow("power", "Open at Login", $settings.launchAtLogin)
                        Divider().opacity(0.4)
                        if let newVersion = updates.availableVersion {
                            // Only ever shown when there is something to say —
                            // a permanent "you're up to date" row would be
                            // noise in a menu this small.
                            menuButton("arrow.down.circle.fill",
                                       "Update to \(newVersion)",
                                       tint: .accentColor) {
                                updates.installUpdate()
                            }
                        }
                        menuButton("gearshape", "Settings…", shortcut: ",", action: onOpenSettings)
                        menuButton("arrow.up.to.line", "Reposition", action: onReposition)
                        menuButton("xmark.circle", "Quit AloeNotch", shortcut: "q") {
                            NSApp.terminate(nil)
                        }
                    }
                    .padding(11)
                    .panelSurface(cornerRadius: 16, glass: settings.useGlass)

                    if option.revealed || debug.isActive {
                        DebugSection()
                            .padding(11)
                            .panelSurface(cornerRadius: 16, glass: settings.useGlass)
                    }
                }
            .padding(12)
        }
        .onAppear { option.start() }
        .onDisappear { option.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            option.start()
        }
        .frame(width: 268)
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .foregroundStyle(.tint)
            Text("AloeNotch")
                .font(.body.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func toggleRow(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.callout)
                Spacer()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    @ViewBuilder
    private func menuButton(_ symbol: String, _ title: String,
                            tint: Color? = nil,
                            shortcut: Character? = nil,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.callout).frame(width: 18)
                Text(title).font(.callout)
                Spacer()
                // Shown the way a real menu shows it, and bound below so it
                // works while this window is open.
                if let shortcut {
                    Text("⌘\(String(shortcut).uppercased())")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)

        if let shortcut {
            button.keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        } else {
            button
        }
    }
}

/// Hidden behind ⌥: tools for looking at motion, not features.
private struct DebugSection: View {
    @ObservedObject private var debug = DebugTools.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Debug", systemImage: "ladybug")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Reset") { debug.reset() }
                    .font(.callout)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!debug.isActive)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Slow motion").font(.callout)
                    Spacer()
                    Text(String(format: "%.2g×", debug.slowMotion))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $debug.slowMotion, in: DebugTools.slowMotionRange, step: 0.05)
                    .controlSize(.mini)
            }

            Toggle(isOn: $debug.showFrameTimes) {
                Text("Frame-time overlay").font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 8) {
                Button("Next state") { debug.advance() }
                    .controlSize(.small)
                Menu(debug.step?.title ?? "Jump to…") {
                    ForEach(DebugTools.Step.allCases) { step in
                        Button(step.title) { debug.run(step) }
                    }
                }
                .controlSize(.small)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button(debug.isBenchmarking ? "Benchmarking…" : "Benchmark solid vs glass") {
                debug.runBenchmark()
            }
            .controlSize(.small)
            .disabled(debug.isBenchmarking)

            if let report = debug.benchmark {
                Text(report)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Whether ⌥ has been held since the dropdown opened — at the click, or at
/// any point while it is open, the way a system menu swaps in its ⌥ items.
/// Stays revealed until the dropdown closes so the key can be let go.
private final class OptionKeyWatcher: ObservableObject {
    @Published private(set) var revealed = false
    private var monitor: Any?

    func start() {
        if NSEvent.modifierFlags.contains(.option) { revealed = true }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.modifierFlags.contains(.option) { self?.revealed = true }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        revealed = false
    }

    deinit { stop() }
}
