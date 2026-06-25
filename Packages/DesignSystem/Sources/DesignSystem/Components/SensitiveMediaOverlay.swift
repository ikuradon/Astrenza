import SwiftUI

public struct SensitiveMediaOverlay: View {
    @Environment(\.appTheme) private var theme

    private let title: String
    private let message: String

    public init(title: String = "Sensitive media", message: String = "Open the post to view this media.") {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DSSpacing.md.cgFloat) {
            Image(systemName: DSIcon.sensitive.systemName)
                .font(DSIcon.sensitive.font(for: .timelineAction, weight: .bold))
                .foregroundStyle(theme.color(.warning))

            Text(title)
                .font(DSTypography.captionEmphasized.font)
                .foregroundStyle(theme.color(.textPrimary))

            Text(message)
                .font(DSTypography.caption.font)
                .foregroundStyle(theme.color(.textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(DSSpacing.xxl.cgFloat)
        .frame(maxWidth: .infinity, minHeight: CGFloat(DSMediaMetrics.timeline.minimumReservedHeight))
        .background(theme.color(.cardBackground), in: RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous)
                .stroke(theme.color(.separator), lineWidth: DSSpacing.hairline.cgFloat)
        }
    }
}
