import SwiftUI

/// One-time first-run welcome.
///
/// AloeNotch is invisible until you hover the notch — which is the point, but it
/// also means a brand-new user launches the app and sees nothing happen. This
/// screen teaches the gesture (with a looping animation), says what's inside,
/// and lets permissions be requested afterwards, in context.
///
/// Built on Liquid Glass over a frosted, behind-window backdrop, so the actual
/// desktop shows through rather than a painted background. Cards go through
/// `panelSurface`, which honours the user's glass preference — offered right
/// here in the footer, because translucency is a taste call and some desktops
/// make it hard to read.
struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onDone: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 0) {
                // The cards are taller than any window we'd want to open at, and
                // this used to be a plain VStack in a fixed frame — so the
                // overflow was simply clipped and "Get Started" was unreachable.
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        features
                        footer
                    }
                    // Top inset clears the traffic lights: the content view now
                    // runs full-height under the titlebar.
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)

                // Pinned, so the primary action can never scroll out of reach.
                actionBar
            }
        }
        .frame(width: 480, height: 640)
        .frostedWindowBackground(settings.useGlass)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Button("Get Started", action: onDone)
                .glassProminentButtonStyle(settings.useGlass)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 4)

            Text("Welcome to AloeNotch")
                .font(.system(size: 22, weight: .semibold))

            Text("Your notch is awake. Hover it to open — it stays invisible until you do.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            MiniNotchDemo().padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .panelSurface(cornerRadius: 26, glass: settings.useGlass)
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("music.note", "Now Playing",
                "Controls for whatever your Mac is playing — Music, Spotify, even YouTube in a browser.")
            row("tray.full", "Shelf",
                "Drag files onto the notch to park them, then drag them back out. They persist across launches.")
            row("calendar", "Calendar & weather",
                "Your week and the local conditions, at a glance.")
            row("gearshape", "Settings",
                "The gear in the panel — or the menu bar icon — changes what shows up.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface(cornerRadius: 22, glass: settings.useGlass)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 14) {
            Toggle("Use Liquid Glass", isOn: $settings.useGlass.animation(.smooth(duration: 0.35)))
                .toggleStyle(.switch)
            Text("Translucent panels that pick up what's behind them. Turn it off for solid panels if you'd rather have the contrast.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            Toggle("Open AloeNotch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)

            Text("Calendar and weather will ask permission after you continue. Both are optional and can be turned off in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .panelSurface(cornerRadius: 22, glass: settings.useGlass)
    }
}

/// A small looping animation of the notch expanding, so the hover gesture reads
/// instantly. Reuses the app's real `NotchShape` so it matches what they'll see.
private struct MiniNotchDemo: View {
    @State private var open = false
    @State private var timer: Timer?

    var body: some View {
        ZStack(alignment: .top) {
            // A dark plate rather than glass: the notch itself must read as a
            // true black cutout, and glass behind it would lift the blacks.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }

            NotchShape(cornerRadius: open ? 14 : 7)
                .fill(.black)
                .frame(width: open ? 226 : 94, height: open ? 66 : 18)
                .overlay(alignment: .bottom) {
                    if open {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(0.22))
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Capsule().fill(.white.opacity(0.30)).frame(width: 58, height: 5)
                                Capsule().fill(.white.opacity(0.16)).frame(width: 38, height: 5)
                            }
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(0.14))
                                .frame(width: 40, height: 26)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 11)
                        .transition(.opacity)
                    }
                }
        }
        .frame(width: 262, height: 104)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation(.snappy(duration: 0.45, extraBounce: 0.12)) { open.toggle() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
