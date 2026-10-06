import SwiftUI

/// A small animated lightning bolt shown in the collapsed strip while charging.
/// Under Reduce Motion it holds still at full strength. The two states are
/// separate views, so turning the setting on mid-pulse drops the running
/// loop with the view rather than leaving it to finish.
struct BatteryBolt: View {
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion { glyph } else { Pulsing(glyph: glyph) }
    }

    private var glyph: some View {
        Image(systemName: "bolt.fill")
            .font(Typography.icon(10, .bold))
            .foregroundStyle(.green)
    }

    private struct Pulsing<Glyph: View>: View {
        let glyph: Glyph
        @State private var pulse = false

        var body: some View {
            glyph
                .opacity(pulse ? 1.0 : 0.4)
                .onAppear {
                    withAnimation(Motion.ambientPulse.repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }
}

/// Expanded battery pill: a fill bar that tops up with an animated shimmer while
/// charging, plus the percentage.
struct BatteryView: View {
    @ObservedObject var battery: BatteryMonitor
    @Environment(\.notchReduceMotion) private var reduceMotion

    private var percent: Int { Int((battery.level * 100).rounded()) }

    private var fillColor: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.level < 0.2 { return .red }
        return Ink.primary
    }

    var body: some View {
        // Desktop Macs and Macs on a dead battery service report no battery at
        // all. Previously this dimmed to 40% and showed a full-looking pill,
        // which is worse than showing nothing: a permanently greyed-out "100%"
        // reads as a bug rather than as "not applicable".
        if battery.isPresent {
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: 7) {
            batteryGlyph
            Text("\(percent)%")
                .font(Typography.body(.semibold))
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Motion.contentFade, value: percent)
            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(Typography.icon(10, .bold))
                    .foregroundStyle(.green)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Ink.fill, in: Capsule())
    }

    private var batteryGlyph: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Ink.tertiary, lineWidth: 1)
                .frame(width: 28, height: 13)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: max(2, (geo.size.width - 4) * battery.level))
                    .padding(2)
                    .overlay(chargingShimmer)
                    .animation(Motion.contentFade, value: battery.level)
            }
            .frame(width: 28, height: 13)
        }
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Ink.tertiary)
                .frame(width: 2, height: 6)
                .offset(x: 3)
        }
    }

    /// The sweep is decoration, not information — the bolt beside the
    /// percentage already says "charging" — so Reduce Motion drops it.
    @ViewBuilder
    private var chargingShimmer: some View {
        if battery.isCharging && !reduceMotion {
            ChargingShimmer()
                .mask(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct ChargingShimmer: View {
    @State private var shimmer = false

    var body: some View {
        LinearGradient(
            colors: [.clear, Ink.tertiary, .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 12)
        .offset(x: shimmer ? 24 : -24)
        .onAppear {
            withAnimation(Motion.chargeShimmer.repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }
}
