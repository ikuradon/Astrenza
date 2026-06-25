import SwiftUI

public struct LinkPreviewCardModel: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var host: String
    public var mode: LinkPreviewMode

    public init(title: String, subtitle: String, host: String, mode: LinkPreviewMode = .fixedCompactCard) {
        self.title = title
        self.subtitle = subtitle
        self.host = host
        self.mode = mode
    }
}

public struct LinkPreviewCard: View {
    @Environment(\.appTheme) private var theme

    private let model: LinkPreviewCardModel
    private let metrics: DSMediaMetrics

    public init(model: LinkPreviewCardModel, metrics: DSMediaMetrics = .timeline) {
        self.model = model
        self.metrics = metrics
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.xl.cgFloat) {
            RoundedRectangle(cornerRadius: DSRadius.sm.cgFloat, style: .continuous)
                .fill(theme.color(.placeholder))
                .frame(width: imageWidth, height: imageHeight)

            VStack(alignment: .leading, spacing: DSSpacing.xs.cgFloat) {
                Text(model.host)
                    .font(DSTypography.captionEmphasized.font)
                    .foregroundStyle(theme.color(.textTertiary))
                    .lineLimit(1)

                Text(model.title)
                    .font(DSTypography.bodyEmphasized.font)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(2)

                Text(model.subtitle)
                    .font(DSTypography.caption.font)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(2)
            }
            .frame(
                minHeight: CGFloat(linkPreviewMetrics.textAreaMinHeight),
                maxHeight: CGFloat(linkPreviewMetrics.textAreaMaxHeight),
                alignment: .topLeading
            )
        }
        .padding(DSSpacing.xl.cgFloat)
        .frame(maxHeight: CGFloat(linkPreviewMetrics.totalMaxHeight), alignment: .top)
        .background(theme.color(.cardBackground), in: RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous)
                .stroke(theme.color(.separator), lineWidth: DSSpacing.hairline.cgFloat)
        }
    }

    private var linkPreviewMetrics: DSLinkPreviewMetrics {
        metrics.linkPreview
    }

    private var imageWidth: CGFloat {
        model.mode == .urlOnly ? 0 : CGFloat(linkPreviewMetrics.compactImageWidth)
    }

    private var imageHeight: CGFloat {
        model.mode == .urlOnly ? 0 : CGFloat(linkPreviewMetrics.compactImageHeight)
    }
}
