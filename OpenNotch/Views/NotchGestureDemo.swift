import SwiftUI

/// A looping demonstration of the hover gesture, for the onboarding flow.
///
/// This carries more weight than a normal illustration. AloeNotch draws nothing
/// until the pointer reaches the notch, so a new user who never discovers the
/// gesture experiences the app as broken — they launch it and nothing happens.
/// Words alone don't fix that; showing the movement does.
///
/// So the loop has a cursor in it. The earlier version animated only the notch
/// opening and closing, which demonstrates the *result* without ever showing
/// the *action* that causes it. The pointer travelling up into the notch is the
/// part that actually teaches.
struct NotchGestureDemo: View {
    /// Overall scale. The onboarding uses a larger one than the compact
    /// version that used to sit in the welcome card.
    var scale: CGFloat = 1.0

    @State private var phase: Phase = .idle
    @State private var timer: Timer?
    @ObservedObject private var a11y = AccessibilityPreferences.shared

    /// Where in the loop we are. Modelled explicitly rather than as a pair of
    /// booleans so the pointer and the panel can never disagree about it.
    private enum Phase {
        case idle          // pointer parked below, notch closed
        case approaching   // pointer travelling up
        case open          // notch expanded, pointer resting on it
        case leaving       // pointer heading back down

        var notchOpen: Bool { self == .open }
    }

    private var reduceMotion: Bool { a11y.reduceMotion }

    var body: some View {
        ZStack(alignment: .top) {
            // The "screen" the notch lives on.
            RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                .fill(.black.opacity(0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }

            notch

            if !reduceMotion {
                pointer
            }
        }
        .frame(width: 300 * scale, height: 150 * scale)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: reduceMotion) { _, reduce in
            // Under Reduce Motion the loop stops and the notch rests open, so
            // the layout still explains itself without anything moving.
            if reduce {
                stop()
                phase = .open
            } else {
                start()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Demonstration: moving the pointer to the notch opens the panel.")
    }

    // MARK: Pieces

    private var notch: some View {
        NotchShape(cornerRadius: (phase.notchOpen ? 14 : 7) * scale)
            .fill(.black)
            .frame(width: (phase.notchOpen ? 240 : 100) * scale,
                   height: (phase.notchOpen ? 74 : 20) * scale)
            .overlay(alignment: .bottom) {
                if phase.notchOpen {
                    HStack(spacing: 9 * scale) {
                        RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .frame(width: 30 * scale, height: 30 * scale)
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Capsule().fill(.white.opacity(0.30))
                                .frame(width: 66 * scale, height: 5 * scale)
                            Capsule().fill(.white.opacity(0.16))
                                .frame(width: 44 * scale, height: 5 * scale)
                        }
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                            .fill(.white.opacity(0.14))
                            .frame(width: 44 * scale, height: 30 * scale)
                    }
                    .padding(.horizontal, 13 * scale)
                    .padding(.bottom, 12 * scale)
                    .transition(.opacity)
                }
            }
    }

    /// A stylised pointer that rises into the notch and falls away again.
    private var pointer: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 17 * scale, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .offset(y: pointerY)
            .opacity(phase == .idle ? 0 : 1)
    }

    /// Vertical travel, measured from the top of the frame. Parked below the
    /// panel when idle, tucked just under the notch when open.
    private var pointerY: CGFloat {
        switch phase {
        case .idle:        120 * scale
        case .approaching: 120 * scale
        case .open:        44 * scale
        case .leaving:     120 * scale
        }
    }

    // MARK: Loop

    private func start() {
        guard !reduceMotion else { phase = .open; return }
        guard timer == nil else { return }
        advance()
        timer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { _ in advance() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One beat of the loop. The pointer moves first and the notch follows,
    /// because that is the causal order the demo is teaching — reversing them
    /// would show a panel that opens on its own.
    private func advance() {
        withAnimation(.smooth(duration: 0.55)) { phase = .approaching }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.snappy(duration: 0.45, extraBounce: 0.12)) { phase = .open }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.smooth(duration: 0.45)) { phase = .leaving }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            withAnimation(.easeOut(duration: 0.2)) { phase = .idle }
        }
    }
}
