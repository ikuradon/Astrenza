import SwiftUI

public struct QuoteCardModel: Equatable, Sendable {
    public var author: TimelineAuthorBlockModel
    public var body: String
    public var mode: QuoteCardMode

    public init(author: TimelineAuthorBlockModel, body: String, mode: QuoteCardMode = .collapsedCard) {
        self.author = author
        self.body = body
        self.mode = mode
    }
}

public struct QuoteCardView: View {
    @Environment(\.appTheme) private var theme

    private let model: QuoteCardModel
    private let maxLines: Int

    public init(model: QuoteCardModel, maxLines: Int = TimelineRowLayoutContract.homeTextOnly.maxQuoteLines) {
        self.model = model
        self.maxLines = maxLines
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.md.cgFloat) {
            AvatarView(initials: model.author.displayName, size: TimelineRowMetrics().avatarSize * 0.6)

            VStack(alignment: .leading, spacing: DSSpacing.sm.cgFloat) {
                TimelineAuthorBlock(model: model.author)

                Text(model.body)
                    .font(DSTypography.body.font)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineSpacing(DSTypography.body.style.lineSpacing)
                    .lineLimit(maxLines)
            }
        }
        .padding(DSSpacing.xl.cgFloat)
        .background(theme.color(.cardBackground), in: RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card.cgFloat, style: .continuous)
                .stroke(theme.color(.separator), lineWidth: DSSpacing.hairline.cgFloat)
        }
    }
}
