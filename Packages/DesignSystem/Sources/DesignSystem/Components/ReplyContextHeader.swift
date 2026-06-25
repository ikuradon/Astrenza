import SwiftUI

public struct ReplyContextHeader: View {
    @Environment(\.appTheme) private var theme

    private let authorText: String
    private let contextText: String

    public init(authorText: String, contextText: String) {
        self.authorText = authorText
        self.contextText = contextText
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            Image(systemName: DSIcon.reply.systemName)
                .font(DSIcon.reply.font(for: .compactBadge, weight: .semibold))
                .foregroundStyle(theme.color(.reply))

            Text(authorText)
                .font(DSTypography.captionEmphasized.font)
                .foregroundStyle(theme.color(.textSecondary))
                .lineLimit(1)

            Text(contextText)
                .font(DSTypography.caption.font)
                .foregroundStyle(theme.color(.textTertiary))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
