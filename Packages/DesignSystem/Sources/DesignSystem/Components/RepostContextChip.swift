import SwiftUI

public struct RepostContextChip: View {
    @Environment(\.appTheme) private var theme

    private let text: String
    private let metrics: TimelineContextChipMetrics

    public init(text: String, metrics: TimelineContextChipMetrics = .repostCompact) {
        self.text = text
        self.metrics = metrics
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            Image(systemName: DSIcon.repost.systemName)
                .font(.system(size: CGFloat(metrics.iconSize), weight: .bold))

            Text(text)
                .font(DSTypography.captionEmphasized.font)
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(.repost))
        .padding(.horizontal, DSSpacing.lg.cgFloat)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .frame(minHeight: CGFloat(metrics.minimumFrameHeight))
        .background(theme.color(.repost).opacity(0.12), in: Capsule())
    }

    private var maxWidth: CGFloat? {
        metrics.maxWidth.map { CGFloat($0) }
    }
}
