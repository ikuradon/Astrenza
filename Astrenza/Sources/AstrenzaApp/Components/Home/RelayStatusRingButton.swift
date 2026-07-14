import SwiftUI

struct RelayStatusRingButton: View {
    let connected: Int
    let planned: Int
    let collapseProgress: CGFloat
    let isProcessing: Bool
    let processingLabel: String?
    @State private var processingRotation: Double = 0

    private var progress: Double {
        guard planned > 0 else { return 0 }
        return min(Double(connected) / Double(planned), 1)
    }

    private var labelProgress: CGFloat {
        1 - collapseProgress
    }

    private var ringSize: CGFloat {
        30 - (2 * collapseProgress)
    }

    private var containerWidth: CGFloat {
        104 - (56 * collapseProgress)
    }

    var body: some View {
        HStack(spacing: 8 * labelProgress) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [Color.astrenzaAccent, .cyan, Color.astrenzaAccent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if isProcessing {
                    Circle()
                        .trim(from: 0.08, to: 0.38)
                        .stroke(
                            Color.white.opacity(0.84),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .padding(7)
                        .rotationEffect(.degrees(processingRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                processingRotation = 360
                            }
                        }
                        .onDisappear {
                            processingRotation = 0
                        }
                }
                Text("\(connected)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: 0) {
                Text("Relays")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(processingLabel ?? "\(connected)/\(planned)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .scaleEffect(x: labelProgress, y: labelProgress, anchor: .leading)
            .frame(width: 45 * labelProgress, alignment: .leading)
            .clipped()
            .opacity(Double(labelProgress))
        }
        .padding(.leading, 9 - (2 * collapseProgress))
        .padding(.trailing, 11 - (3 * collapseProgress))
        .frame(width: containerWidth, height: 46 - (2 * collapseProgress))
        .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
        .contentShape(Capsule())
        .animation(.spring(duration: 0.36, bounce: 0.16), value: collapseProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let base = "Show relay information, \(connected) of \(planned) recently reachable"
        guard let processingLabel else { return base }
        return "\(base), \(processingLabel) in progress"
    }
}
