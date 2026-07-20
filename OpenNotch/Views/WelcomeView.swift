import SwiftUI

/// One-time first-run welcome.
///
/// AloeNotch is invisible until you hover the notch — which is the point, but it
/// also means a brand-new user launches the app and sees nothing happen. This
/// screen teaches the gesture (with a looping animation), says what's inside,
/// and lets permissions be requested afterwards, in context.
struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            features
            Divider()
            footer
        }
        .frame(width: 460)
    }

    private var header: some View {
        VStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
            Text("Welcome to AloeNotch")
                .font(.system(size: 21, weight: .semibold))
            Text("Your notch is awake. Hover it to open — it stays invisible until you do.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            MiniNotchDemo().padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 13) {
            row("music.note", "Now Playing",
                "Controls for whatever your Mac is playing — Music, Spotify, even YouTube in a browser.")
            row("tray.full", "Shelf",
                "Drag files onto the notch to park them, then drag them back out. They persist across launches.")
            row("calendar", "Calendar & weather",
                "Your week and the local conditions, at a glance.")
            row("gearshape", "Settings",
                "The gear in the panel — or the menu bar icon — changes what shows up.")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            Toggle("Open AloeNotch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
            Text("Calendar and weather will ask permission after you continue. Both are optional and can be turned off in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Get Started", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }
}

/// A small looping animation of the notch expanding, so the hover gesture reads
/// instantly. Reuses the app's real `NotchShape` so it matches what they'll see.
private struct MiniNotchDemo: View {
    @State private var open = false
    @State private var timer: Timer?

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))

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
