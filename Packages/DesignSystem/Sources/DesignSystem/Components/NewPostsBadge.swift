import SwiftUI

public struct NewPostsBadge: View {
    @Environment(\.appTheme) private var theme

    private let count: Int
    private let action: () -> Void

    public init(count: Int, action: @escaping () -> Void = {}) {
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs.cgFloat) {
                Image(systemName: DSIcon.newPosts.systemName)
                    .font(DSIcon.newPosts.font(for: .compactBadge, weight: .bold))

                Text(label)
                    .font(DSTypography.badge.font)
            }
            .foregroundStyle(theme.color(.textPrimary))
            .padding(.horizontal, DSSpacing.xxl.cgFloat)
            .frame(minHeight: CGFloat(DSControlSize.minimumHitTarget))
            .background(theme.color(.accent), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline.newPostsBadge")
    }

    private var label: String {
        count == 1 ? "1 new post" : "\(count) new posts"
    }
}
