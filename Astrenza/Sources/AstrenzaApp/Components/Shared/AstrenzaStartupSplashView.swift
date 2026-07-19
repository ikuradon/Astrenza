import SwiftUI

struct AstrenzaStartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let startDate: Date
    let status: NostrTimelineActivityStatus

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let showsRelayRing = elapsed >= 0.8
            let showsStatusText = elapsed >= 1.5
            let showsStatusDetail = elapsed >= 2.1

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: AstrenzaSpacing.point14) {
                    ZStack {
                        if showsRelayRing {
                            RelayStartupRing(progressDate: elapsed)
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }

                        AstrenzaLogoMark(
                            size: 58,
                            backgroundColor: AstrenzaPalette.Logo.darkBackground,
                            strokeColor: Color.white.opacity(0.16),
                            shadowColor: Color.black.opacity(0.24)
                        )
                        .scaleEffect(iconScale(elapsed: elapsed))
                    }
                    .frame(width: 92, height: 92)

                    VStack(spacing: AstrenzaSpacing.point4) {
                        Text(status.title)
                            .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .contentTransition(.opacity)

                        Text(status.detail)
                            .font(.astrenza(.point10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.44))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(showsStatusDetail ? 1 : 0)
                    }
                    .frame(maxWidth: 280)
                    .opacity(showsStatusText ? 1 : 0)
                    .offset(y: showsStatusText ? 0 : 4)
                    .animation(.easeOut(duration: AstrenzaMotion.fast), value: showsStatusText)
                    .animation(.easeOut(duration: AstrenzaMotion.fast), value: showsStatusDetail)
                    .animation(.easeInOut(duration: AstrenzaMotion.quick), value: status)
                }
            }
            .animation(.easeOut(duration: AstrenzaMotion.fast), value: showsRelayRing)
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
