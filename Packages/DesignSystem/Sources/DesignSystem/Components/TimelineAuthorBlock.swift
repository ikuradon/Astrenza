import SwiftUI

public struct TimelineAuthorBlockModel: Equatable, Sendable {
    public var displayName: String
    public var handle: String
    public var timestampText: String?
    public var isVerified: Bool
    public var isLocked: Bool

    public init(
        displayName: String,
        handle: String,
        timestampText: String? = nil,
        isVerified: Bool = false,
        isLocked: Bool = false
    ) {
        self.displayName = displayName
        self.handle = handle
        self.timestampText = timestampText
        self.isVerified = isVerified
        self.isLocked = isLocked
    }
}

public struct TimelineAuthorBlock: View {
    @Environment(\.appTheme) private var theme

    private let model: TimelineAuthorBlockModel

    public init(model: TimelineAuthorBlockModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs.cgFloat) {
            HStack(spacing: DSSpacing.xs.cgFloat) {
                Text(model.displayName)
                    .font(DSTypography.authorName.font)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if model.isLocked {
                    Image(systemName: DSIcon.lock.systemName)
                        .font(DSIcon.lock.font(for: .compactBadge, weight: .semibold))
                        .foregroundStyle(theme.color(.textTertiary))
                }
            }

            HStack(spacing: DSSpacing.xs.cgFloat) {
                Text(model.handle)
                    .font(DSTypography.authorHandle.font)
                    .foregroundStyle(theme.color(model.isVerified ? .accent : .textSecondary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let timestampText = model.timestampText {
                    Text(timestampText)
                        .font(DSTypography.caption.font)
                        .foregroundStyle(theme.color(.textTertiary))
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
