import SwiftUI

/// A small animated lightning bolt shown in the collapsed strip while charging.
struct BatteryBolt: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.green)
            .opacity(pulse ? 1.0 : 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Expanded battery pill: a fill bar that tops up with an animated shimmer while
/// charging, plus the percentage.
struct BatteryView: View {
    @ObservedObject var battery: BatteryMonitor
    @State private var shimmer = false

    private var percent: Int { Int((battery.level * 100).rounded()) }

    private var fillColor: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.level < 0.2 { return .red }
        return .white.opacity(0.85)
    }

    var body: some View {
        HStack(spacing: 7) {
            batteryGlyph
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: percent)
            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.white.opacity(0.08), in: Capsule())
        .opacity(battery.isPresent ? 1 : 0.4)
    }

    private var batteryGlyph: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 28, height: 13)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: max(2, (geo.size.width - 4) * battery.level))
                    .padding(2)
                    .overlay(chargingShimmer)
                    .animation(.easeInOut(duration: 0.4), value: battery.level)
            }
            .frame(width: 28, height: 13)
        }
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.5))
                .frame(width: 2, height: 6)
                .offset(x: 3)
        }
    }

    @ViewBuilder
    private var chargingShimmer: some View {
        if battery.isCharging {
            LinearGradient(
                colors: [.clear, .white.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 12)
            .offset(x: shimmer ? 24 : -24)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
            .mask(RoundedRectangle(cornerRadius: 2))
        }
    }
}
