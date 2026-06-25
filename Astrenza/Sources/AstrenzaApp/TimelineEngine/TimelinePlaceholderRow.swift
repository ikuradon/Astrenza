import DesignSystem
import SwiftUI

struct TimelinePlaceholderRow: View {
    @Environment(\.appTheme) private var theme

    let entryID: TimelineEntryID
    private let metrics = TimelineRowMetrics()

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(metrics.avatarToContentGap)) {
            DesignSystem.AvatarView(initials: "TE", size: metrics.avatarSize)

            VStack(alignment: .leading, spacing: DSSpacing.sm.cgFloat) {
                DesignSystem.TimelineAuthorBlock(model: authorModel)

                DesignSystem.ContentWarningPill("TimelineEngine scaffold")

                Text("Non-production UICollectionView placeholder row.")
                    .font(DSTypography.body.font)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineSpacing(DSTypography.body.style.lineSpacing)
                    .lineLimit(TimelineRowLayoutContract.homeTextOnly.maxBodyLinesInCollapsedMode)

                Text(entryID.rawValue)
                    .font(DSTypography.caption.font)
                    .foregroundStyle(theme.color(.textTertiary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                DesignSystem.TimelineActionBar(items: placeholderActions, metrics: metrics.actionMetrics)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CGFloat(metrics.horizontalPadding))
        .padding(.top, CGFloat(metrics.verticalPaddingTop))
        .padding(.bottom, CGFloat(metrics.verticalPaddingBottom))
        .background(theme.color(.rowBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.color(.separator))
                .frame(height: DSSpacing.hairline.cgFloat)
        }
    }

    private var authorModel: TimelineAuthorBlockModel {
        TimelineAuthorBlockModel(
            displayName: "TimelineEngine",
            handle: "scaffold only",
            timestampText: "debug",
            isVerified: false,
            isLocked: true
        )
    }

    private var placeholderActions: [TimelineActionBarItem] {
        [
            TimelineActionBarItem(id: "reply", icon: .reply, accessibilityLabel: "Reply"),
            TimelineActionBarItem(id: "repost", icon: .repost, accessibilityLabel: "Repost"),
            TimelineActionBarItem(id: "reaction", icon: .reaction, accessibilityLabel: "Reaction"),
            TimelineActionBarItem(id: "share", icon: .share, accessibilityLabel: "Share"),
            TimelineActionBarItem(id: "more", icon: .more, accessibilityLabel: "More")
        ]
    }
}
