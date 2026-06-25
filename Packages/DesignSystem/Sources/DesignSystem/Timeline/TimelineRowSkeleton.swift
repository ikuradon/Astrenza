import SwiftUI

public enum TimelineRowSkeletonStyle: String, CaseIterable, Codable, Sendable {
    case textOnly
    case media
    case quote
    case linkPreview
}

public struct TimelineRowSkeleton: View {
    @Environment(\.appTheme) private var theme

    private let style: TimelineRowSkeletonStyle
    private let metrics: TimelineRowMetrics

    public init(style: TimelineRowSkeletonStyle = .textOnly, metrics: TimelineRowMetrics = TimelineRowMetrics()) {
        self.style = style
        self.metrics = metrics
    }

    public var body: some View {
        HStack(alignment: .top, spacing: CGFloat(metrics.avatarToContentGap)) {
            Circle()
                .fill(theme.color(.placeholder))
                .frame(width: CGFloat(metrics.avatarSize), height: CGFloat(metrics.avatarSize))

            VStack(alignment: .leading, spacing: DSSpacing.md.cgFloat) {
                RoundedRectangle(cornerRadius: DSRadius.xs.cgFloat, style: .continuous)
                    .fill(theme.color(.placeholder))
                    .frame(width: CGFloat(metrics.avatarSize * 2.4), height: DSSpacing.xl.cgFloat)

                RoundedRectangle(cornerRadius: DSRadius.xs.cgFloat, style: .continuous)
                    .fill(theme.color(.placeholder))
                    .frame(height: DSSpacing.xl.cgFloat)

                if style != .textOnly {
                    RoundedRectangle(cornerRadius: CGFloat(metrics.cardCornerRadius), style: .continuous)
                        .fill(theme.color(.cardBackground))
                        .frame(height: reservedHeight)
                }
            }
        }
        .padding(.horizontal, CGFloat(metrics.horizontalPadding))
        .padding(.top, CGFloat(metrics.verticalPaddingTop))
        .padding(.bottom, CGFloat(metrics.verticalPaddingBottom))
        .background(theme.color(.rowBackground))
        .accessibilityHidden(true)
    }

    private var reservedHeight: CGFloat {
        switch style {
        case .textOnly:
            0
        case .media:
            CGFloat(DSMediaMetrics.timeline.minimumReservedHeight)
        case .quote, .linkPreview:
            CGFloat(DSMediaMetrics.timeline.minimumReservedHeight * 0.72)
        }
    }
}
