import SwiftUI

public struct ContentWarningPill: View {
    @Environment(\.appTheme) private var theme

    private let text: String
    private let metrics: TimelineContextChipMetrics

    public init(_ text: String, metrics: TimelineContextChipMetrics = .contentWarningPill) {
        self.text = text
        self.metrics = metrics
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            Image(systemName: DSIcon.warning.systemName)
                .font(DSIcon.warning.font(size: metrics.iconSize, weight: .bold))

            Text(text)
                .font(DSTypography.badge.font)
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(.warning))
        .padding(.horizontal, DSSpacing.xl.cgFloat)
        .frame(minHeight: CGFloat(metrics.minimumFrameHeight))
        .background(theme.color(.warning).opacity(0.14), in: Capsule())
    }
}
