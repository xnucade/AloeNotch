import SwiftUI
import Combine
import EventKit
import CoreLocation

/// First-run onboarding: a short, animated, multi-step flow.
///
/// AloeNotch is invisible until you hover the notch — which is the point, but it
/// also means a brand-new user launches the app and sees nothing happen. This
/// flow exists to close that gap, and it is also the first thing anyone sees of
/// the app's quality, so it is built to be looked at rather than skipped.
///
/// Permissions are requested *here*, in context, one screen at a time, with the
/// reason next to each. The alternative — firing three system prompts at launch
/// before the user knows what the app is — is how apps get denied by reflex.
struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var a11y = AccessibilityPreferences.shared
    let onDone: () -> Void

    @State private var step: Step = .welcome
    /// Direction of travel, so the slide transition leans the right way when
    /// going back rather than always sliding forward.
    @State private var goingBack = false

    enum Step: Int, CaseIterable, Comparable {
        case welcome, gesture, permissions, finish
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 30)
                .padding(.top, 40)

            footer
        }
        .frame(width: 520, height: 560)
        .frostedWindowBackground(settings.useGlass)
        .withAccessibilityPreferences()
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch step {
            case .welcome:     welcomeStep
            case .gesture:     gestureStep
            case .permissions: permissionsStep
            case .finish:      finishStep
            }
        }
        .transition(stepTransition)
        .id(step)
    }

    /// Slides in the direction of travel. Under Reduce Motion it degrades to a
    /// plain cross-fade — the flow still reads as stepping forward because the
    /// progress dots move, without anything sliding across the screen.
    private var stepTransition: AnyTransition {
        if a11y.reduceMotion { return .opacity }
        let from: Edge = goingBack ? .leading : .trailing
        let to: Edge = goingBack ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: from).combined(with: .opacity),
            removal: .move(edge: to).combined(with: .opacity)
        )
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 5)

            VStack(spacing: 8) {
                Text("Welcome to AloeNotch")
                    .font(.system(size: 26, weight: .semibold))
                Text("Your MacBook's notch, turned into something useful.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 13) {
                highlight("music.note", "Now Playing",
                          "Whatever your Mac is playing — Music, Spotify, even YouTube.")
                highlight("tray.full", "Shelf",
                          "Drop files on the notch to park them, then drag them back out.")
                highlight("calendar", "Your day",
                          "Next event, local weather and battery, at a glance.")
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }

    private var gestureStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Hover the notch")
                    .font(.system(size: 24, weight: .semibold))
                Text("That's the whole gesture. AloeNotch stays completely invisible until your pointer reaches the top of the screen.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NotchGestureDemo(scale: 1.0)

            Text("Try it after you finish setting up.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("A few optional permissions")
                    .font(.system(size: 22, weight: .semibold))
                Text("Every one of these is optional, and each only switches off a single feature. You can change them any time in Settings.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingPermissions()

            Spacer(minLength: 0)
        }
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("You're set")
                    .font(.system(size: 24, weight: .semibold))
                Text("The notch is live. Hover it whenever you want it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                SettingsRow("Open AloeNotch at login", symbol: "power",
                            description: "It runs quietly in the menu bar.") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Liquid Glass", symbol: "square.on.square.dashed",
                            description: "Translucent windows. Turn it off if you'd rather have solid panels.") {
                    Toggle("", isOn: $settings.useGlass.animation(
                        Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion)))
                        .labelsHidden()
                }
            }
            .panelSurface(cornerRadius: 12, glass: settings.useGlass)

            Spacer(minLength: 0)
        }
    }

    private func highlight(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            HStack {
                Button("Back") { go(to: previous) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(step == .welcome ? 0 : 1)
                    .disabled(step == .welcome)

                Spacer()
                progressDots
                Spacer()

                Button(step == .finish ? "Get Started" : "Continue") {
                    if step == .finish { onDone() } else { go(to: next) }
                }
                .glassProminentButtonStyle(settings.useGlass)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.35)))
                    .frame(width: 6, height: 6)
                    .scaleEffect(s == step && !a11y.reduceMotion ? 1.25 : 1)
            }
        }
        .animation(Motion.resolve(Motion.micro, reduceMotion: a11y.reduceMotion), value: step)
    }

    private var next: Step { Step(rawValue: step.rawValue + 1) ?? .finish }
    private var previous: Step { Step(rawValue: step.rawValue - 1) ?? .welcome }

    private func go(to destination: Step) {
        goingBack = destination < step
        withAnimation(Motion.resolve(Motion.contentFade, reduceMotion: a11y.reduceMotion)) {
            step = destination
        }
    }
}

/// The three optional permissions, each requestable inline.
///
/// Shares `PermissionRow` with the Settings pane deliberately: the same
/// permission should not be described two different ways depending on where the
/// user happens to read about it.
private struct OnboardingPermissions: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionRequester.shared

    /// Accessibility can only be polled; the other two publish their own changes.
    @State private var accessibilityTrusted = MediaKeyInterceptor.isTrusted
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PermissionRow(
                title: "Calendar",
                symbol: "calendar",
                rationale: permissions.calendarStatus == .denied
                    ? "Denied. You can allow it later in System Settings → Privacy & Security."
                    : "Shows your next event in the panel. Nothing leaves your Mac.",
                status: permissions.calendarGranted ? .granted
                      : (permissions.calendarStatus == .denied ? .denied : .notDetermined),
                action: (permissions.calendarGranted || permissions.calendarStatus == .denied)
                    ? nil : { permissions.requestCalendar() }
            )
            SettingsDivider()
            PermissionRow(
                title: "Location",
                symbol: "location",
                rationale: permissions.locationStatus == .denied
                    ? "Denied. You can allow it later in System Settings → Privacy & Security."
                    : "Used at reduced accuracy for local weather — roughly your city, not your address.",
                status: permissions.locationGranted ? .granted
                      : (permissions.locationStatus == .denied ? .denied : .notDetermined),
                action: (permissions.locationGranted || permissions.locationStatus == .denied)
                    ? nil : { permissions.requestLocation() }
            )
            SettingsDivider()
            PermissionRow(
                title: "Accessibility",
                symbol: "hand.raised",
                rationale: "Lets AloeNotch show volume and brightness in the notch instead of the macOS HUD.",
                status: accessibilityTrusted ? .granted : .notDetermined,
                action: accessibilityTrusted ? nil : { MediaKeyInterceptor.requestTrust() }
            )
        }
        .panelSurface(cornerRadius: 12, glass: settings.useGlass)
        .onReceive(poll) { _ in
            accessibilityTrusted = MediaKeyInterceptor.isTrusted
            permissions.refresh()
        }
    }
}
