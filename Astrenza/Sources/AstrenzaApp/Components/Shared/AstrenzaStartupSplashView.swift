import SwiftUI

struct AstrenzaStartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let startDate: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let showsRelayRing = elapsed >= 0.8
            let showsStatusText = elapsed >= 1.5

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 14) {
                    ZStack {
                        if showsRelayRing {
                            RelayStartupRing(progressDate: elapsed)
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }

                        AstrenzaLogoMark(
                            size: 58,
                            backgroundColor: Color(red: 0.96, green: 0.91, blue: 1.0),
                            strokeColor: Color.white.opacity(0.16),
                            shadowColor: Color.black.opacity(0.24)
                        )
                        .scaleEffect(iconScale(elapsed: elapsed))
                    }
                    .frame(width: 92, height: 92)

                    Text("Connecting relays...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                        .opacity(showsStatusText ? 1 : 0)
                        .offset(y: showsStatusText ? 0 : 4)
                        .animation(.easeOut(duration: 0.18), value: showsStatusText)
                }
            }
            .animation(.easeOut(duration: 0.18), value: showsRelayRing)
        }
        .allowsHitTesting(true)
        .accessibilityHidden(true)
    }

    private func iconScale(elapsed: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let cycle = sin(elapsed * .pi * 2 / 1.35)
        return 1 + CGFloat(cycle) * 0.018
    }
}

private struct RelayStartupRing: View {
    let progressDate: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 2)
            Circle()
                .trim(from: 0.06, to: 0.42)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.astrenzaAccent.opacity(0.15),
                            Color.astrenzaAccent,
                            Color.cyan.opacity(0.85)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(progressDate * 190))
        }
        .frame(width: 82, height: 82)
    }
}
